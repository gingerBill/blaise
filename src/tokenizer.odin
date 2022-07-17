package main

import "core:unicode/utf8"

Pos :: struct {
	offset: int,
	line:   int,
	column: int,
}

Token :: struct {
	using pos: Pos,
	kind: Token_Kind,
	text: string,
}

Error :: enum {
	None,

	EOF, // Not necessarily an error

	Illegal_Character,
}

Token_Kind :: enum {
	Invalid,
	EOF,

	Ident,

	Integer,

	Period,
	Colon,
	Comma,
	Semicolon,

	Open_Brace,
	Close_Brace,

	Open_Paren,
	Close_Paren,

	Var,
	Const,
	Proc,

	Input,
	Print,
	Call,
	Odd,

	If,
	Else,
	While,
	Repeat,

	Assign,

	Eq,
	Lt,
	LtEq,
	Gt,
	GtEq,
	NotEq,
	Add,
	Sub,
	Mul,
	Div,
	Mod,
}

Tokenizer :: struct {
	using pos:        Pos,
	data:             string,
	r:                rune, // current rune
	w:                int,  // current rune width in bytes
	curr_line_offset: int,
	insert_semicolon: bool,
}

token_string_table := [Token_Kind]string{
	.Invalid       = "Invalid",
	.EOF           = "EOF",

	.Ident         = "identifier",

	.Integer       = "integer",

	.Period        = ".",
	.Colon         = "colon",
	.Comma         = "comma",
	.Semicolon     = "semicolon",

	.Open_Brace    = "{",
	.Close_Brace   = "}",

	.Open_Paren    = "(",
	.Close_Paren   = ")",

	.Var       = "var",
	.Const     = "const",
	.Proc      = "proc",

	.Input     = "input",
	.Print     = "print",
	.Call      = "call",
	.Odd       = "odd",

	.If        = "if",
	.Else      = "else",
	.While     = "while",
	.Repeat    = "repeat",


	.Assign    = ":=",

	.Eq        = "=",
	.Lt        = "<",
	.LtEq      = "<=",
	.Gt        = ">",
	.GtEq      = ">=",
	.NotEq     = "!=",
	.Add       = "+",
	.Sub       = "-",
	.Mul       = "*",
	.Div       = "/",
	.Mod       = "%",
}


token_string :: proc(tok: Token) -> string {
	if tok.kind == .Semicolon && tok.text == "\n" {
		return "newline"
	}
	return token_string_table[tok.kind]
}


tokenizer_init :: proc(t: ^Tokenizer, data: string) {
	t^ = Tokenizer{pos = {line=1}, data = data}
	next_rune(t)
	if t.r == utf8.RUNE_BOM {
		next_rune(t)
	}
}

next_rune :: proc(t: ^Tokenizer) -> rune #no_bounds_check {
	if t.offset >= len(t.data) {
		t.r = utf8.RUNE_EOF
	} else {
		t.offset += t.w
		t.r, t.w = utf8.decode_rune_in_string(t.data[t.offset:])
		t.pos.column = t.offset - t.curr_line_offset
		if t.offset >= len(t.data) {
			t.r = utf8.RUNE_EOF
		}
	}
	return t.r
}


get_token :: proc(t: ^Tokenizer) -> (token: Token, err: Error) {
	skip_whitespace :: proc(t: ^Tokenizer, on_newline: bool) {
		loop: for t.offset < len(t.data) {
			switch t.r {
			case ' ', '\t', '\v', '\f', '\r':
				next_rune(t)
			case '\n':
				if on_newline {
					break loop
				}
				t.line += 1
				t.curr_line_offset = t.offset
				t.pos.column = 1
				next_rune(t)
			case:
				switch t.r {
				case 0x2028, 0x2029, 0xFEFF:
					next_rune(t)
					continue loop
				}
				break loop
			}
		}
	}

	skip_whitespace(t, t.insert_semicolon)

	token.pos = t.pos

	token.kind = .Invalid

	curr_rune := t.r
	next_rune(t)

	block: switch curr_rune {
	case utf8.RUNE_ERROR:
		err = .Illegal_Character

	case utf8.RUNE_EOF, '\x00':
		token.kind = .EOF
		err = .EOF

	case '\n':
		// If this is reached, treat a newline as if it is a semicolon
		t.insert_semicolon = false
		token.text = "\n"
		token.kind = .Semicolon
		t.line += 1
		t.curr_line_offset = t.offset
		t.pos.column = 1
		return

	case 'A'..='Z', 'a'..='z', '_':
		token.kind = .Ident

		for t.offset < len(t.data) {
			switch t.r {
			case 'A'..='Z', 'a'..='z', '0'..='9', '_':
				next_rune(t)
				continue
			}
			break
		}

		// This could easily be a `map[string]Token_Kind`
		switch str := string(t.data[token.offset:t.offset]); str {
		case "var":   token.kind = .Var
		case "const": token.kind = .Const
		case "proc":  token.kind = .Proc

		case "input": token.kind = .Input
		case "print": token.kind = .Print
		case "call":  token.kind = .Call
		case "odd":   token.kind = .Odd

		case "if":     token.kind = .If
		case "else":   token.kind = .Else
		case "while":  token.kind = .While
		case "repeat": token.kind = .Repeat
		}

	case '0'..='9':
		token.kind = .Integer
		if curr_rune == '0' && (t.r == 'x' || t.r == 'X') {
			next_rune(t)
			for t.offset < len(t.data) {
				switch t.r {
				case '0'..='9', 'a'..='f', 'A'..='F':
					next_rune(t)
					continue
				}
				break
			}
			break
		}

		for t.offset < len(t.data) && '0' <= t.r && t.r <= '9' {
			next_rune(t)
		}


	case ':':
		token.kind = .Colon
		if t.r == '=' {
			next_rune(t)
			token.kind = .Assign
		}

	case '+': token.kind = .Add
	case '-': token.kind = .Sub
	case '*': token.kind = .Mul
	case '%': token.kind = .Mod

	case '.': token.kind = .Period
	case ',': token.kind = .Comma
	case ';': token.kind = .Semicolon
	case '{': token.kind = .Open_Brace
	case '}': token.kind = .Close_Brace
	case '(': token.kind = .Open_Paren
	case ')': token.kind = .Close_Paren

	case '=': token.kind = .Eq
	case '<':
		token.kind = .Lt
		if t.r == '=' {
			next_rune(t)
			token.kind = .LtEq
		}
	case '>':
		token.kind = .Gt
		if t.r == '=' {
			next_rune(t)
			token.kind = .GtEq
		}
	case '!':
		token.kind = .Invalid
		if t.r == '=' {
			next_rune(t)
			token.kind = .NotEq
		}

	case '/':
		token.kind = .Div

		switch t.r {
		case '/':
			// Single-line comments
			for t.offset < len(t.data) {
				r := next_rune(t)
				if r == '\n' {
					break
				}
			}
			return get_token(t)
		case '*':
			// None-nested multi-line comments
			for t.offset < len(t.data) {
				next_rune(t)
				if t.r == '*' {
					next_rune(t)
					if t.r == '/' {
						next_rune(t)
						return get_token(t)
					}
				}
			}
			err = .EOF
		}

	case:
		err = .Illegal_Character
	}

	#partial switch token.kind {
	case .Invalid:
		// preserve insert_semicolon info

	case .EOF, .Semicolon:
		t.insert_semicolon = false

	case .Ident, .Integer,
	     .Close_Brace, .Close_Paren:
		t.insert_semicolon = true

	case:
		t.insert_semicolon = false
	}

	token.text = string(t.data[token.offset : t.offset])
	return
}
