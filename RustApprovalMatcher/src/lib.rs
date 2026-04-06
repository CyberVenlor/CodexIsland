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

    if contains_dynamic_or_unsafe_shell_syntax(trimmed) {
        return true;
    }

    let tokens = shell_tokens(trimmed);
    if tokens.is_empty() {
        return true;
    }

    !shell_structure_is_safe(&tokens)
}

fn contains_dynamic_or_unsafe_shell_syntax(command: &str) -> bool {
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

        if character == '`' || character == '>' || character == '<' {
            return true;
        }

        if character == '$' && chars.get(index + 1) == Some(&'(') {
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

        if let Some(operator) = shell_operator(&chars, index) {
            if !current.is_empty() {
                tokens.push(std::mem::take(&mut current));
            }
            index += operator.len();
            tokens.push(operator.to_string());
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

fn shell_structure_is_safe(tokens: &[String]) -> bool {
    let mut index = 0;
    parse_block(tokens, &mut index, &[]).is_some() && index == tokens.len()
}

fn parse_block(tokens: &[String], index: &mut usize, terminators: &[&str]) -> Option<()> {
    while *index < tokens.len() {
        let token = tokens[*index].as_str();

        if terminators.contains(&token) {
            return Some(());
        }

        if is_command_separator(token) {
            *index += 1;
            continue;
        }

        match token {
            "if" => parse_if(tokens, index)?,
            "while" | "until" => parse_while(tokens, index)?,
            "for" => parse_for(tokens, index)?,
            "case" => parse_case(tokens, index)?,
            "then" | "do" | "else" | "elif" | "fi" | "done" | "esac" | "in" => return None,
            _ => parse_simple_command(tokens, index)?,
        }
    }

    Some(())
}

fn parse_if(tokens: &[String], index: &mut usize) -> Option<()> {
    *index += 1;

    loop {
        parse_block(tokens, index, &["then", "elif", "else", "fi"])?;
        let token = tokens.get(*index)?.as_str();

        match token {
            "then" => {
                *index += 1;
                parse_block(tokens, index, &["elif", "else", "fi"])?;
                let next = tokens.get(*index)?.as_str();
                match next {
                    "elif" => {
                        *index += 1;
                    }
                    "else" => {
                        *index += 1;
                        parse_block(tokens, index, &["fi"])?;
                        if tokens.get(*index)?.as_str() != "fi" {
                            return None;
                        }
                        *index += 1;
                        return Some(());
                    }
                    "fi" => {
                        *index += 1;
                        return Some(());
                    }
                    _ => return None,
                }
            }
            "elif" => {
                *index += 1;
            }
            "else" => {
                *index += 1;
                parse_block(tokens, index, &["fi"])?;
                if tokens.get(*index)?.as_str() != "fi" {
                    return None;
                }
                *index += 1;
                return Some(());
            }
            "fi" => {
                *index += 1;
                return Some(());
            }
            _ => return None,
        }
    }
}

fn parse_while(tokens: &[String], index: &mut usize) -> Option<()> {
    *index += 1;
    parse_block(tokens, index, &["do"])?;
    if tokens.get(*index)?.as_str() != "do" {
        return None;
    }
    *index += 1;
    parse_block(tokens, index, &["done"])?;
    if tokens.get(*index)?.as_str() != "done" {
        return None;
    }
    *index += 1;
    Some(())
}

fn parse_for(tokens: &[String], index: &mut usize) -> Option<()> {
    *index += 1;

    while *index < tokens.len() {
        match tokens[*index].as_str() {
            "do" => {
                *index += 1;
                parse_block(tokens, index, &["done"])?;
                if tokens.get(*index)?.as_str() != "done" {
                    return None;
                }
                *index += 1;
                return Some(());
            }
            ">" | ">>" | "<" | "<<" | "<<<" => return None,
            _ => *index += 1,
        }
    }

    None
}

fn parse_case(tokens: &[String], index: &mut usize) -> Option<()> {
    *index += 1;

    while *index < tokens.len() && tokens[*index].as_str() != "in" {
        if matches!(tokens[*index].as_str(), ">" | ">>" | "<" | "<<" | "<<<") {
            return None;
        }
        *index += 1;
    }

    if tokens.get(*index)?.as_str() != "in" {
        return None;
    }
    *index += 1;

    while *index < tokens.len() {
        if tokens[*index].as_str() == "esac" {
            *index += 1;
            return Some(());
        }

        while *index < tokens.len() && tokens[*index].as_str() != ")" {
            if tokens[*index].as_str() == "esac" {
                *index += 1;
                return Some(());
            }
            *index += 1;
        }

        if *index >= tokens.len() || tokens[*index].as_str() != ")" {
            return None;
        }
        *index += 1;

        parse_block(tokens, index, &[";;", "esac"])?;
        match tokens.get(*index)?.as_str() {
            ";;" => *index += 1,
            "esac" => {
                *index += 1;
                return Some(());
            }
            _ => return None,
        }
    }

    None
}

fn parse_simple_command(tokens: &[String], index: &mut usize) -> Option<()> {
    let start = *index;

    while *index < tokens.len() {
        let token = tokens[*index].as_str();
        if is_command_separator(token) || matches!(token, "then" | "do" | "else" | "elif" | "fi" | "done" | "esac" | ";;") {
            break;
        }
        if matches!(token, ">" | ">>" | "<" | "<<" | "<<<") {
            return None;
        }
        *index += 1;
    }

    validate_command(&tokens[start..*index])
}

fn validate_command(tokens: &[String]) -> Option<()> {
    if tokens.is_empty() {
        return Some(());
    }

    let mut command_index = 0;
    while command_index < tokens.len() && looks_like_environment_assignment(&tokens[command_index]) {
        command_index += 1;
    }

    if command_index >= tokens.len() {
        return Some(());
    }

    let executable = Path::new(&tokens[command_index])
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(tokens[command_index].as_str());

    let command_tokens = &tokens[command_index..];

    if is_safe_inspection_command(executable, command_tokens) {
        return Some(());
    }

    let safe = match executable {
        "git" => is_safe_git_command(command_tokens),
        "swift" => is_safe_swift_command(command_tokens),
        "xcodebuild" => is_safe_xcodebuild_command(command_tokens),
        "npm" | "pnpm" | "yarn" | "bun" => is_safe_javascript_command(command_tokens),
        _ => false,
    };

    safe.then_some(())
}

fn shell_operator(chars: &[char], index: usize) -> Option<&'static str> {
    let current = *chars.get(index)?;
    let next = chars.get(index + 1).copied();

    match (current, next) {
        ('&', Some('&')) => Some("&&"),
        ('|', Some('|')) => Some("||"),
        (';', Some(';')) => Some(";;"),
        ('>', Some('>')) => Some(">>"),
        ('<', Some('<')) => Some("<<"),
        ('|', _) => Some("|"),
        (';', _) => Some(";"),
        ('(', _) => Some("("),
        (')', _) => Some(")"),
        ('>', _) => Some(">"),
        ('<', _) => Some("<"),
        _ => None,
    }
}

fn is_command_separator(token: &str) -> bool {
    matches!(token, "|" | "&&" | "||" | ";")
}

fn looks_like_environment_assignment(token: &str) -> bool {
    let Some((key, _)) = token.split_once('=') else {
        return false;
    };

    !key.is_empty() && key.chars().all(|character| character.is_ascii_alphanumeric() || character == '_')
}

fn is_safe_inspection_command(executable: &str, tokens: &[String]) -> bool {
    match executable {
        "cat" | "cut" | "du" | "env" | "fd" | "file" | "grep" | "head" | "less" | "ls"
        | "printenv" | "pwd" | "rg" | "sort" | "stat" | "tail" | "tree" | "uname" | "uniq"
        | "wc" | "whereis" | "which" | "whoami" | "awk" => true,
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
