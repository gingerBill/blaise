package main

import "core:fmt"
import "core:os"
import "core:bytes"
import "core:strconv"
import "core:path/filepath"

Entity :: struct {
	kind:      Token_Kind,
	name:      string,
	value:     i32,
	addr:      u32,
	is_global: bool,
	procedure: ^Procedure,
}

Entity_Table :: distinct map[string]Entity

Procedure :: struct {
	parent: ^Procedure,
	name:        string,
	addr:        u32,
	local_count: u32,
	is_global:   bool,
	entities:    Entity_Table,
}

Checker :: struct {
	scopes:         map[string]^Procedure,
	curr_procedure: ^Procedure,
	tokenizer:      Tokenizer,
	prev_token:     Token,
	curr_token:     Token,

	filename: string,
	fatalf:   proc(c: ^Checker, pos: Pos, format: string, args: ..any) -> !,
}

default_fatalf :: proc(c: ^Checker, pos: Pos, format: string, args: ..any) -> ! {
	fmt.eprintf("%s(%d:%d) ", c.filename, pos.line, pos.column)
	fmt.eprintf(format, ..args)
	fmt.eprintln()
	os.exit(1)
}

compile :: proc(filename: string) {
	imports := create_imports()
	bytes.buffer_write(&gen.code, imports)

	data, ok := os.read_entire_file(filename)
	assert(ok)
	defer delete(data)

	c := &Checker{}
	c.filename, _ = filepath.abs(filename)
	tokenizer_init(&c.tokenizer, string(data))
	next(c)
	parse_program(c)

	gen_exit()

	buf := bytes.buffer_to_bytes(&gen.code)

	// fixup labels
	{
		b := buf[len(imports):]
		for label := gen.labels; label != nil; label = label.next {
			put_i32(b[label.pc:], i32(label.jmp))
		}
	}

	res_path := fmt.aprintf("%s.exe", filepath.stem(filename))

	write_exe(res_path, bytes.buffer_to_bytes(&gen.code), imports)
}


// Grammar related procedures


next :: proc(c: ^Checker) -> (res: Token) {
	token, err := get_token(&c.tokenizer)
	if err != nil && token.kind != .EOF {
		c->fatalf(token.pos, "found invalid token: %v", err)
	}
	c.prev_token, c.curr_token = c.curr_token, token
	return c.prev_token
}
expect :: proc(c: ^Checker, kind: Token_Kind) -> Token {
	token := next(c)
	if token.kind != kind {
		c->fatalf(token.pos, "expected %q, got %s", token_string_table[kind], token_string(token))
	}
	return token
}
allow :: proc(c: ^Checker, kind: Token_Kind) -> bool {
	if c.curr_token.kind == kind {
		next(c)
		return true
	}
	return false
}
peek :: proc(c: ^Checker) -> Token_Kind {
	return c.curr_token.kind
}

declare :: proc(c: ^Checker, pos: Pos, name: string, kind: Token_Kind, value: i32) {
	p := c.curr_procedure
	if name in p.entities {
		c->fatalf(pos, "redeclaration of '%s'", name)
	}
	addr: u32
	if p.is_global {
		addr = gen.data_p
		gen.data_p += 4
		gen_global_var(value)
	} else {
		addr = p.local_count * 4
		p.local_count += 1
	}

	p.entities[name] = Entity{
		kind = kind,
		name = name,
		value = value,
		addr = addr,
		procedure = p,
		is_global = p.is_global,
	}
}


/*
	const_decl = "const" ident ":=" number {"," ident "=" number} ";" ;
*/
const_decl :: proc(c: ^Checker) {
	expect(c, .Const)
	for {
		name := expect(c, .Ident)
		expect(c, .Assign)
		val_tok := expect(c, .Integer)
		val, ok := strconv.parse_i64(val_tok.text)
		assert(ok)
		declare(c, name.pos, name.text, .Const, i32(val))
		if allow(c, .Semicolon) {
			break
		}
		expect(c, .Comma)
	}
}

/*
	var_decl = "var" ident [":=" number] {"," ident [":=" number]} ";"  ;
*/
var_decl :: proc(c: ^Checker) {
	expect(c, .Var)
	for {
		value := i32(0)
		name := expect(c, .Ident)
		if allow(c, .Assign) {
			val, ok := strconv.parse_i64(expect(c, .Integer).text)
			assert(ok)
			value = i32(val)
		}

		declare(c, name.pos, name.text, .Var, value)
		if allow(c, .Semicolon) {
			break
		}
		expect(c, .Comma)
	}
}

/*
	value_decls = { [const_decl] [var_decl] } ;
*/
value_decls :: proc(c: ^Checker) {
	for {
		#partial switch peek(c) {
		case .Const:
			const_decl(c)
		case .Var:
			var_decl(c)
		case:
			return
		}
	}
}


push_procedure :: proc(c: ^Checker, scope: string) -> ^Procedure {
	p := new_clone(Procedure{
		entities  = make(Entity_Table),
		name      = scope,
		is_global = scope == "",
		parent    = c.curr_procedure,
	})
	c.scopes[scope] = p
	c.curr_procedure = p
	return p
}

pop_procedure :: proc(c: ^Checker) {
	c.curr_procedure = c.curr_procedure.parent
}

check_ident :: proc(c: ^Checker, tok: Token, is_assignment: bool) -> Entity {
	name := tok.text
	e, ok := c.curr_procedure.entities[name]
	if ok {
		if is_assignment && e.kind != .Var {
			c->fatalf(tok.pos, "expected a variable, got '%s'", name)
		}
		return e
	}
	e, ok = c.scopes[""].entities[name]
	if ok {
		if is_assignment && e.kind != .Var {
			c->fatalf(tok.pos, "expected a variable, got '%s'", name)
		}
		return e
	}
	c->fatalf(tok.pos, "undeclared name '%s'", name)
	return e
}

/*
	factor = ident | number | "(" expression ")";
*/
factor :: proc(c: ^Checker) {
	tok := next(c)
	#partial switch tok.kind {
	case .Ident:
		e := check_ident(c, tok, false)
		gen_ident(c, e)
	case .Integer:
		val, ok := strconv.parse_i64(tok.text)
		assert(ok)
		gen_imm(c, i32(val))
	case .Open_Paren:
		expression(c)
		expect(c, .Close_Paren)
	case:
		c->fatalf(tok.pos, "invalid factor, got %s", token_string(tok))
	}
}

/*
	term = factor {("*"|"/"|"%") factor};
*/
term :: proc(c: ^Checker) {
	factor(c)
	for {
		op := peek(c)
		#partial switch op {
		case .Mul: next(c); factor(c); gen_mul()
		case .Div: next(c); factor(c); gen_div()
		case .Mod: next(c); factor(c); gen_mod()
		case: return
		}
	}
}

/*
	expression = ["+"|"-"] term {["+"|"-"] term};
*/
expression :: proc(c: ^Checker) {
	neg := false
	if allow(c, .Sub) {
		neg = true
	} else if allow(c, .Add) {
		//
	}
	term(c)
	if neg {
		gen_neg()
	}
	for {
		op := peek(c)
		if op != .Add && op != .Sub {
			break
		}
		next(c)
		term(c)
		if op == .Add {
			gen_add()
		} else {
			gen_sub()
		}
	}
}

/*
	condition = "odd" expression |
	            expression ("="|"!="|"<"|"<="|">"|">=") expression;
*/
@(require_results)
condition :: proc(c: ^Checker) -> ^Label {
	if allow(c, .Odd) {
		expression(c)
		return gen_odd()
	}

	expression(c)
	cond := next(c)
	expression(c)

	#partial switch cond.kind {
	case .Eq, .NotEq, .Lt, .LtEq, .Gt, .GtEq:
		// okay
	case:
		c->fatalf(cond.pos, "comparison operator expected, got %s", token_string(cond))
	}
	return gen_cond(cond.kind)
}

/*
	procedure_body = "{" value_decls statement_list "}";
*/
procedure_body :: proc(c: ^Checker) {
	expect(c, .Open_Brace)

	value_decls(c)
	c.curr_procedure.addr = gen.pc
	gen_proc(c.curr_procedure, .Head)

	for peek(c) != .Close_Brace {
		statement(c)
		if !allow(c, .Semicolon) {
			break
		}
	}
	expect(c, .Close_Brace)
	gen_proc(c.curr_procedure, .Tail)
}

/*
	statement_list = statement {";" statement} [";"] ;
*/
statement_list :: proc(c: ^Checker, end: Token_Kind) {
	for peek(c) != end {
		statement(c)
		if !allow(c, .Semicolon) {
			break
		}
	}
}

/*
	block = "{" statement {";" statement} [";"] "}";
*/
block :: proc(c: ^Checker, ignore_begin := false) {
	if !ignore_begin {
		expect(c, .Open_Brace)
	}
	statement_list(c, .Close_Brace)
	expect(c, .Close_Brace)
}

/*
	statement = [ ident ":=" expression
	              | "call" ident
	              | "input" ident
	              | "print" ident
	              | "if" condition block [ "else" statement ]
	              | "while" condition block
	              | "repeat" block "while" condition
	              | block ];
*/
statement :: proc(c: ^Checker) {
	check_call :: proc(c: ^Checker, tok: Token) -> ^Procedure {
		p, ok := c.scopes[tok.text]
		if !ok {
			c->fatalf(tok.pos, "undeclared procedure '%s'", tok.text)
		}
		return p
	}

	tok := next(c)
	#partial switch tok.kind {
	case .Ident:
		// ident ":=" expression
		e := check_ident(c, tok, true)
		expect(c, .Assign)
		expression(c)
		gen_assignment(e)

	case .Call:
		// "call" ident
		procedure := expect(c, .Ident)
		p := check_call(c, procedure)
		gen_call(p)
	case .Input:
		// "input" ident
		e := check_ident(c, expect(c, .Ident), true)
		gen_input(e)
	case .Print:
		// "print" ident
		expression(c)
		gen_print()
	case .If:
		// "if" condition block [ "else" statement ]
		label := condition(c)
		block(c)
		gen_begin_label(label)
		if allow(c, .Else) {
			#partial switch peek(c) {
			case .If, .Open_Brace:
				statement(c)
			case:
				c->fatalf(tok.pos, "expected an if statement or block after 'else'")
			}
		}
	case .While:
		// "while" condition block
		wpc := gen.pc
		label := condition(c)
		block(c)
		gen_jmp(wpc)
		gen_begin_label(label)
	case .Repeat:
		// "repeat" block "while" condition
		rpc := gen.pc
		block(c)
		expect(c, .While)
		label := condition(c)
		gen_jmp(rpc)
		gen_begin_label(label)

	case .Var, .Const, .Proc:
		if c.curr_procedure.is_global {
			c->fatalf(tok.pos, "'%s' declarations must be at the top of the file", tok.text)
		} else {
			c->fatalf(tok.pos, "'%s' declarations must be at the top of the procedure's block", tok.text)
		}
	case .Open_Brace:
		// block
		block(c, true)
	case:
		c->fatalf(tok.pos, "invalid statement, got %s", token_string(tok))
	}
}

/*
	procedure = "proc" ident procedure_body ";" ;
*/
procedure :: proc(c: ^Checker) {
	expect(c, .Proc)
	name := expect(c, .Ident)
	scope := name.text
	if scope in c.scopes {
		c->fatalf(name.pos, "%s redeclared", scope)
	}
	push_procedure(c, scope)
	procedure_body(c)
	pop_procedure(c)
	expect(c, .Semicolon)
}

/*
	program = { [const_decl] [var_decl] [procedure] }
	               statement {";" statement} [";"] EOF ;
*/
parse_program :: proc(c: ^Checker) {
	if c.fatalf == nil {
		c.fatalf = default_fatalf
	}

	global := push_procedure(c, "")
	defer pop_procedure(c)

	decls: for {
		#partial switch peek(c) {
		case .Const:
			const_decl(c)
		case .Var:
			var_decl(c)
		case .Proc:
			procedure(c)
		case:
			break decls
		}
	}

	gen.ep = TEXT_BASE + IMPORT_SIZE + gen.pc

	assert(c.curr_procedure == global)

	statement_list(c, .EOF)

	allow(c, .Semicolon)
	expect(c, .EOF)
}


/*

program = { [const_decl] [var_decl] [procedure] }
            statement_list EOF ;

statement_list = statement {";" statement} [";"] ;

const_decl = "const" ident ":=" number {"," ident "=" number} ";" ;

var_decl = "var" ident [":=" number] {"," ident [":=" number]} ";"  ;

value_decls = { [const_decl] [var_decl] } ;

procedure = "proc" ident "{" value_decls statement_list "}" ";" ;

statement = [ ident ":=" expression
              | "call" ident
              | "input" ident
              | "print" ident
              | "if" condition block [ "else" statement ]
              | "while" condition block
              | "repeat" block "while" condition
              | block ];

expression = ["+"|"-"] term {["+"|"-"] term};

term = factor {("*"|"/"|"%") factor};

factor = ident | number | "(" expression ")";

condition = "odd" expression |
            expression ("="|"!="|"<"|"<="|">"|">=") expression;

*/