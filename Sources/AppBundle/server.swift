import AppKit
import Common
import Network

func startUnixSocketServer() {
    let runtimeDir = getRuntimeDirPath(appId: hyprSpaceAppId)
    switch checkRuntimeDir(runtimeDir, createIfMissing: true) {
        case .ok: break
        case .missing: die("Can't create the socket directory '\(runtimeDir)'")
        case .unsafe(let msg): die("The socket directory is not safe to use: \(msg)")
    }
    try? FileManager.default.removeItem(atPath: socketPath)
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = .unix(path: socketPath)
    let listener = Result { try NWListener(using: params) }.getOrDie()
    listener.newConnectionHandler = { connection in
        Task.startUnstructured {
            defer { connection.cancel() }
            connection.start(queue: .global())
            await newConnection(connection)
        }
    }
    listener.stateUpdateHandler = { state in
        // Without the socket the CLI client can't reach the server. Don't keep running as if nothing has happened
        if case .failed(let error) = state {
            die("Can't listen on the socket '\(socketPath)': \(error)")
        }
    }
    listener.start(queue: .global())
}

func toggleReleaseServerIfDebug(_ state: EnableCmdArgs.State) async {
    if serverArgs.isReadOnly { return }
    if !isDebug { return }
    if checkRuntimeDir(getRuntimeDirPath(appId: stableHyprSpaceAppId), createIfMissing: false) != .ok { return }
    let socketFile = getSocketPath(appId: stableHyprSpaceAppId)
    let connection = NWConnection(to: NWEndpoint.unix(path: socketFile), using: .tcp)
    defer { connection.cancel() }
    if await connection.initConnection().error != nil { // Can't connect, HyprSpace.app is not running
        return
    }

    let req = ClientRequest(args: ["enable", state.rawValue], stdin: "", windowId: nil, workspace: nil)
    _ = await connection.writeAtomic(req)
    _ = await connection.readNonAtomic()
}

private let serverVersionAndHash = "\(hyprSpaceAppVersion) \(gitHash)"

private func newConnection(_ connection: NWConnection) async { // todo add exit codes
    func answerToClient(exitCode: Int32, stdout: String = "", stderr: String = "") async {
        let ans = ServerAnswer(exitCode: exitCode, stdout: stdout, stderr: stderr, serverVersionAndHash: serverVersionAndHash)
        await answerToClient(ans)
    }
    func answerToClient(_ ans: ServerAnswer) async {
        _ = await connection.writeAtomic(ans)
    }

    guard let clientVersion = await connection.readUInt32().getIgnoringErrorsOrNil() else { return }
    // The server unconditionally answers with the only version it supports
    if await connection.writeUInt32(SOCKET_PROTOCOL_VERSION).error != nil { return }
    if clientVersion != SOCKET_PROTOCOL_VERSION { return }

    while true {
        guard let rawRequest = await connection.readNonAtomic().getOrNil(onFailure: { err in
            await answerToClient(exitCode: EXIT_CODE_TWO, stderr: "Error: \(err)")
        }) else { return }
        guard let request = await ClientRequest.decodeJson(rawRequest).getOrNil(onFailure: { err in
            let msg = """
                Can't parse request \(String(describing: String(data: rawRequest, encoding: .utf8)).singleQuoted).
                Error: \(err)
                """
            return await answerToClient(exitCode: EXIT_CODE_TWO, stderr: msg)
        }) else { continue }
        // Handle subscribe before parseCommand (subscribe doesn't have a Command impl)
        if request.args.first == "subscribe" {
            switch parseSubscribeCmdArgs(request.args.slice(1...).orDie()) {
                case .cmd(let subscribeArgs): await handleSubscribeAndWaitTillError(connection, subscribeArgs)
                case .help(let help): await answerToClient(exitCode: EXIT_CODE_ZERO, stdout: help)
                case .failure(let err): await answerToClient(exitCode: err.exitCode, stderr: err.msg)
            }
            continue
        }
        let parsedCmd = parseCommand(request.args)
        guard let token: RunSessionGuard = await .isServerEnabled(orIsEnableCommand: parsedCmd.cmdOrNil) else {
            await answerToClient(
                exitCode: EXIT_CODE_TWO,
                stderr: "\(hyprSpaceAppName) server is disabled and doesn't accept commands. " +
                    "You can use 'hyprspace enable on' to enable the server",
            )
            continue
        }
        switch parsedCmd {
            case .help(let help):
                await answerToClient(exitCode: EXIT_CODE_ZERO, stdout: help)
                continue
            case .failure(let err):
                await answerToClient(exitCode: err.exitCode, stderr: err.msg)
                continue
            case .cmd(let command):
                var answer: ServerAnswer =
                    await Result {
                        try await runLightSession(.socketServer(command.args), token) { () throws in
                            let env = CmdEnv.init(
                                windowId: request.windowId.flattenOptional(),
                                workspaceName: request.workspace.flattenOptional(),
                            )
                            let cmdResult = await command.run(env, CmdStdin(request.stdin))
                            return ServerAnswer(
                                exitCode: cmdResult.exitCode.rawValue,
                                stdout: cmdResult.stdout.joined(separator: "\n"),
                                stderr: cmdResult.stderr.joined(separator: "\n"),
                                serverVersionAndHash: serverVersionAndHash,
                            )
                        }
                    }
                    .get { err in
                        ServerAnswer(
                            exitCode: command.args.failExitCode,
                            stderr: "Fail to await main thread. \(err.localizedDescription)",
                            serverVersionAndHash: serverVersionAndHash,
                        )
                    }
                if request.windowId == nil || request.workspace == nil {
                    answer.stderr += "\n\nHyprSpace client has sent incomplete JSON request. 'windowId' or/and 'workspace' fields are missing. Please forward your HYPRSPACE_WINDOW_ID and HYPRSPACE_WORKSPACE environment variables to these JSON fields. If the appropriate environment variables are empty, pass explicit 'null' in the JSON."
                }
                await answerToClient(answer)
                continue
        }
    }
}
