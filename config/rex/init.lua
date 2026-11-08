-- Native Rex sessions, tabs and panes.
rex.bind("ctrl+p", "client.tab.previous")
rex.bind("ctrl+n", "client.tab.next")
rex.bind("ctrl+b>p", "client.tab.previous")
rex.bind("ctrl+b>n", "client.tab.next")
rex.bind("ctrl+b>c", "client.tab.new")
rex.bind("ctrl+b>shift+\\", "pane.split", { direction = "right" })
rex.bind("ctrl+b>-", "pane.split", { direction = "down" })
rex.bind("ctrl+b>s", "session.switch")
rex.bind("ctrl+b>w", "pane.new_floating")
rex.bind("ctrl+b>z", "pane.zoom")
-- Use Rex's native close and activity-based confirmation.
rex.bind("ctrl+b>x", "client.close")
rex.bind("ctrl+b>r", "client.config.reload")
rex.bind("ctrl+b>ctrl+b", "pane.send_key", { key = "ctrl+b" })
for index = 1, 9 do
	rex.bind("ctrl+b>" .. index, "client.tab.goto", { index = index })
end
