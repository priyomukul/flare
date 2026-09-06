import Foundation

/// The Claude Code hooks block, with the port Flare is actually listening on.
///
/// Three "waiting" triggers, because no single one covers everything:
///   Notification   — permission prompts, idle prompts, elicitation dialogs
///   Stop           — end of a turn, i.e. Claude wants the next instruction
///   PreToolUse     — AskUserQuestion, which Notification does not fire for
/// and three "clear" triggers: UserPromptSubmit, PostToolUse(AskUserQuestion),
/// SessionEnd.
///
/// Every command swallows stdout and never fails the hook, because
/// UserPromptSubmit stdout is injected into Claude's context and a hook that
/// exits non-zero would surface an error when Flare simply is not running.
enum HooksSnippet {
    static func json(port: Int) -> String {
        let waiting = command(port: port, route: "waiting")
        let clear = command(port: port, route: "clear")
        return """
        {
          "hooks": {
            "Notification": [
              { "matcher": "permission_prompt|idle_prompt|elicitation_dialog",
                "hooks": [ { "type": "command", "async": true,
                  "command": "\(waiting)" } ] }
            ],
            "Stop": [
              { "hooks": [ { "type": "command", "async": true,
                  "command": "\(waiting)" } ] }
            ],
            "PreToolUse": [
              { "matcher": "AskUserQuestion",
                "hooks": [ { "type": "command", "async": true,
                  "command": "\(waiting)" } ] }
            ],
            "UserPromptSubmit": [
              { "hooks": [ { "type": "command",
                  "command": "\(clear)" } ] }
            ],
            "PostToolUse": [
              { "matcher": "AskUserQuestion",
                "hooks": [ { "type": "command",
                  "command": "\(clear)" } ] }
            ],
            "SessionEnd": [
              { "hooks": [ { "type": "command",
                  "command": "\(clear)" } ] }
            ]
          }
        }
        """
    }

    private static func command(port: Int, route: String) -> String {
        "curl -s -m 1 -X POST http://127.0.0.1:\(port)/\(route) "
            + "-H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1 || true"
    }
}
