@testable import AppBundle
import Common
import Testing

@MainActor
@Suite(.serializedGlobally)
struct FocusAfterCloseTest {
    init() { setUpWorkspacesForTests() }

    @Test func testFocusGoesBackToThePreviouslyFocusedWindow() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let master = TestWindow.new(id: 0, parent: root)
        let stack = TilingContainer.newVTiles(parent: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        TestWindow.new(id: 1, parent: stack)
        assertEquals(master.focusWindow(), true)
        await checkOnFocusChangedCallbacks_nonCancellable() // The refresh session records the focus history

        let new = TestWindow.new(id: 2, parent: stack)
        assertEquals(new.focusWindow(), true)
        await checkOnFocusChangedCallbacks_nonCancellable()

        // The new window closes. Its neighbor in the stack (1) is the most recent one by the tree order...
        new.unbindFromParent()
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 1)
        // ...but the focus must go back to the master, because it was focused before the new window
        preferPreviouslyFocusedWindow(in: workspace, closedWindowId: 2)
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 0)
    }

    @Test func testClosingABackgroundWindowDoesNotChangeTheFocus() async {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        let window0 = TestWindow.new(id: 0, parent: root)
        let window1 = TestWindow.new(id: 1, parent: root)
        let window2 = TestWindow.new(id: 2, parent: root)
        assertEquals(window0.focusWindow(), true)
        await checkOnFocusChangedCallbacks_nonCancellable()
        assertEquals(window1.focusWindow(), true)
        await checkOnFocusChangedCallbacks_nonCancellable()

        window2.unbindFromParent() // A window that was not focused is closed
        preferPreviouslyFocusedWindow(in: workspace, closedWindowId: 2)
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 1)
    }
}
