use std::ffi::{c_char, CStr};
use std::path::Path;

#[no_mangle]
pub extern "C" fn codex_command_requires_approval(
    tool_name: *const c_char,
    command: *const c_char,
) -> i32 {
    let Some(tool_name) = c_string(tool_name) else {
        return 1;
    };
    let Some(command) = c_string(command) else {
        return 1;
    };

    requires_approval(tool_name, command) as i32
}

fn c_string(pointer: *const c_char) -> Option<String> {
    if pointer.is_null() {
        return None;
    }

    let value = unsafe { CStr::from_ptr(pointer) };
    Some(value.to_string_lossy().into_owned())
}

fn requires_approval(tool_name: String, command: String) -> bool {
    if tool_name != "Bash" {
        return true;
    }

    let trimmed = command.trim();
    if trimmed.is_empty() {
        return true;
    }

    if contains_risky_shell_syntax(trimmed) {
        return true;
    }

    let tokens = shell_tokens(trimmed);
    if tokens.is_empty() {
        return true;
    }

    if looks_like_environment_assignment(&tokens[0]) {
        return true;
    }

    let executable = Path::new(&tokens[0])
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(tokens[0].as_str());

    if is_safe_inspection_command(executable, &tokens) {
        return false;
    }

    match executable {
        "git" => !is_safe_git_command(&tokens),
        "swift" => !is_safe_swift_command(&tokens),
        "xcodebuild" => !is_safe_xcodebuild_command(&tokens),
        "npm" | "pnpm" | "yarn" | "bun" => !is_safe_javascript_command(&tokens),
        _ => true,
    }
}

fn contains_risky_shell_syntax(command: &str) -> bool {
    let chars: Vec<char> = command.chars().collect();
    let mut index = 0;
    let mut quote: Option<char> = None;

    while index < chars.len() {
        let character = chars[index];

        match quote {
            Some('\'') => {
                if character == '\'' {
                    quote = None;
                }
                index += 1;
                continue;
            }
            Some('"') => {
                if character == '"' {
                    quote = None;
                    index += 1;
                    continue;
                }

                if character == '\\' {
                    index += 2;
                    continue;
                }

                if character == '`' {
                    return true;
                }

                if character == '$' && chars.get(index + 1) == Some(&'(') {
                    return true;
                }

                index += 1;
                continue;
            }
            _ => {}
        }

        if character == '\\' {
            index += 2;
            continue;
        }

        if character == '\'' || character == '"' {
            quote = Some(character);
            index += 1;
            continue;
        }

        if character == '`' || character == ';' || character == '>' || character == '<' {
            return true;
        }

        if character == '$' && chars.get(index + 1) == Some(&'(') {
            return true;
        }

        if character == '&' {
            return true;
        }

        if character == '|' {
            return true;
        }

        index += 1;
    }

    false
}

fn shell_tokens(command: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let chars: Vec<char> = command.chars().collect();
    let mut index = 0;
    let mut quote: Option<char> = None;

    while index < chars.len() {
        let character = chars[index];

        match quote {
            Some('\'') => {
                if character == '\'' {
                    quote = None;
                } else {
                    current.push(character);
                }
                index += 1;
                continue;
            }
            Some('"') => {
                if character == '"' {
                    quote = None;
                } else if character == '\\' {
                    if let Some(next) = chars.get(index + 1) {
                        current.push(*next);
                        index += 1;
                    }
                } else {
                    current.push(character);
                }
                index += 1;
                continue;
            }
            _ => {}
        }

        if character == '\'' || character == '"' {
            quote = Some(character);
            index += 1;
            continue;
        }

        if character == '\\' {
            if let Some(next) = chars.get(index + 1) {
                current.push(*next);
                index += 2;
            } else {
                index += 1;
            }
            continue;
        }

        if character.is_whitespace() {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
            index += 1;
            continue;
        }

        current.push(character);
        index += 1;
    }

    if !current.is_empty() {
        tokens.push(current);
    }

    tokens
}

fn looks_like_environment_assignment(token: &str) -> bool {
    let Some((key, _)) = token.split_once('=') else {
        return false;
    };

    !key.is_empty() && key.chars().all(|character| character.is_ascii_alphanumeric() || character == '_')
}

fn is_safe_inspection_command(executable: &str, tokens: &[String]) -> bool {
    match executable {
        "cat" | "du" | "fd" | "file" | "grep" | "head" | "ls" | "pwd" | "rg" | "stat" | "tail"
        | "tree" | "uname" | "wc" | "which" | "whoami" => true,
        "sed" => !tokens.iter().skip(1).any(|token| token == "-i" || token == "--in-place"),
        "find" => !tokens.iter().skip(1).any(|token| {
            matches!(token.as_str(), "-delete" | "-exec" | "-execdir" | "-ok" | "-okdir")
        }),
        _ => false,
    }
}

fn is_safe_git_command(tokens: &[String]) -> bool {
    let Some(subcommand) = tokens.get(1).map(String::as_str) else {
        return false;
    };

    match subcommand {
        "status" | "diff" | "log" | "show" | "rev-parse" | "grep" | "ls-files" => true,
        "branch" => {
            tokens.len() == 2
                || tokens
                    .iter()
                    .skip(2)
                    .all(|token| token == "--show-current" || token == "--all")
        }
        _ => false,
    }
}

fn is_safe_swift_command(tokens: &[String]) -> bool {
    let Some(subcommand) = tokens.get(1).map(String::as_str) else {
        return false;
    };

    match subcommand {
        "build" | "test" => true,
        "package" => matches!(
            tokens.get(2).map(String::as_str),
            Some("describe") | Some("dump-package")
        ),
        _ => false,
    }
}

fn is_safe_xcodebuild_command(tokens: &[String]) -> bool {
    tokens.iter().skip(1).any(|token| {
        matches!(token.as_str(), "-list" | "-showBuildSettings" | "build" | "test")
    })
}

fn is_safe_javascript_command(tokens: &[String]) -> bool {
    matches!(tokens.get(1).map(String::as_str), Some("test"))
}
