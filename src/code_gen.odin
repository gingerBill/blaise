package main

import "core:bytes"

regs := []Register{.eax, .ebx, .ecx, .edx, .ebp, .esi, .edi}
Register :: enum u8 {
	eax = 0,
	ecx = 1,
	edx = 2,
	ebx = 3,
	esp = 4,
	ebp = 5,
	esi = 6,
	edi = 7,

	// r8 = 8,
	// r9 = 9,
	// r10 = 10,
	// r11 = 11,
	// r12 = 12,
	// r13 = 13,
	// r14 = 14,
	// r15 = 15,
}

gen: struct {
	code:   bytes.Buffer,
	reg:    i32,
	pc:     u32,
	ep:     u32,
	data_p: u32,

	labels: ^Label,
}

Label :: struct {
	next: ^Label,
	pc:  u32,
	jmp: u32,
}

data_base: u32 = IMAGE_BASE + TEXT_BASE + IMPORT_SIZE
code_base: u32 = IMAGE_BASE + TEXT_BASE + IMPORT_SIZE


INT_SIZE :: 4

splat_u32 :: #force_inline proc(x: u32) -> (a, b, c, d: u8) {
	return u8(x), u8(x>>8), u8(x>>16), u8(x>>24)
}
splat_i32 :: #force_inline proc(x: i32) -> (a, b, c, d: u8) {
	return splat_u32(u32(x))
}
splat :: proc{
	splat_u32,
	splat_i32,
}

emit :: proc(args: ..u8) {
	bytes.buffer_write(&gen.code, args)
	gen.pc += u32(len(args))
}

gen_global_var :: proc(value: i32) {
	emit(splat(value))
	code_base += INT_SIZE
}

gen_proc :: proc(p: ^Procedure, part: enum{Head, Tail}) {
	local_count := p.local_count
	if part == .Head {
		if local_count > 0 {
			// sub esp, local_count*INT_SIZE
			emit(0x81, 0xec)
			emit(splat(local_count * INT_SIZE))
		}
	} else {
		if local_count > 0 {
			// add esp, local_count*INT_SIZE
			emit(0x81, 0xc4)
			emit(splat(local_count * INT_SIZE))
		}
		// ret
		emit(0xc3)
	}
}

gen_inc_reg :: proc(c: ^Checker) {
	if int(gen.reg) >= len(regs) {
		c->fatalf(next(c).pos, "expression nested level has reached maximum")
	}
	gen.reg += 1
}


gen_imm :: proc(c: ^Checker, val: i32) {
	// mov REG, val
	emit(0xb8+u8(regs[gen.reg]))
	emit(splat(val))
	gen_inc_reg(c)
}

gen_neg :: proc() {
	// neg REG
	emit(0xf7)
	emit(0xd8+u8(regs[gen.reg-1]))
}

@(require_results)
gen_placeholder_label :: proc() -> ^Label {
	label := new_clone(Label{nil, gen.pc, 0})
	emit(splat_u32(0x00))
	return label
}

gen_odd :: proc() -> ^Label {
	// test REG, 0x1
	// je LOC
	gen.reg -= 1
	emit(u8(0xf7), u8(0xc0)+u8(regs[gen.reg]), splat_u32(0x01))
	emit(u8(0x0f), u8(0x84)); return gen_placeholder_label()
}

gen_exit :: proc() {
	// push 0x0
	// call DWORD PTR ds:imp_exit
	// add ESP, 0x4
	emit(0x6a, 0x00)
	emit(0xff, 0x15, splat(imp_exit))
	emit(u8(0x83), u8(0xc4), u8(0x04))
}

gen_push :: proc(reg: Register) {
	// push REG
	emit(u8(0x50)+u8(reg))
}

gen_pop :: proc(reg: Register) {
	// pop REG
	emit(u8(0x58)+u8(reg))
}

gen_ident_mem :: proc(e: Entity) {
	assert(e.kind == .Var)
	if e.is_global {
		// add REG, data_base+addr
		emit(0x05+u8(regs[gen.reg])*8, splat(data_base + e.addr))
	} else {
		emit(0x84+u8(regs[gen.reg])*8)
		emit(0x24, splat(e.addr))
	}
}

gen_ident :: proc(c: ^Checker, e: Entity) {
	if e.kind == .Const {
		// mov REG, val
		gen_imm(c, e.value)
		return
	}
	// mov REG, MEM
	emit(u8(0x8b))
	gen_ident_mem(e)
	gen_inc_reg(c)
}

gen_assignment :: proc(e: Entity) {
	gen.reg -= 1
	// mov MEM, REG
	emit(u8(0x89))
	gen_ident_mem(e)
}

@(require_results)
gen_cond :: proc(cond: Token_Kind) -> ^Label {
	r0 := u8(regs[gen.reg-2])
	r1 := u8(regs[gen.reg-1])
	// cmp REG0, REG1
	emit(0x39, 0xc0 + r1*8 + r0)
	gen.reg -= 2

	op_code: u8
	#partial switch cond {
	case .Eq:    op_code = 0x85 // jne
	case .NotEq: op_code = 0x84 // je
	case .Lt:    op_code = 0x8d // jnl
	case .LtEq:  op_code = 0x8f // jg
	case .Gt:    op_code = 0x8e // jng
	case .GtEq:  op_code = 0x8c // jl
	case:
		unreachable()
	}
	// OP_CODE LOC
	emit(0x0f, op_code)
	return gen_placeholder_label()
}

gen_begin_label :: proc(label: ^Label) {
	label.jmp = gen.pc - (label.pc + 4)
	label.next = gen.labels
	gen.labels = label
}

gen_jmp :: proc(jpc: u32) {
	// jmp LOC
	jmp := jpc - (gen.pc + 5)
	emit(0xe9, splat(jmp))
}


gen_add :: proc() {
	gen.reg -= 1
	r0 := u8(regs[gen.reg-1])
	r1 := u8(regs[gen.reg])
	// add REG0, REG1
	emit(0x01, 0xc0 + r1*8 + r0)
}
gen_sub :: proc() {
	gen.reg -= 1
	r0 := u8(regs[gen.reg-1])
	r1 := u8(regs[gen.reg])
	// sub REG0, REG1
	emit(0x29, 0xc0 + r1*8 + r0)
}
gen_mul :: proc() {
	gen.reg -= 1
	r0 := u8(regs[gen.reg-1])
	r1 := u8(regs[gen.reg])
	// imul REG0, REG1
	emit(0x0f, 0xaf, 0xc0+r0*8+r1)
}
gen_div :: proc() {
	if gen.reg > 2 {
		for i in 0..<gen.reg {
			gen_push(regs[i])
		}
		gen_pop(.ebx)
		gen_pop(.eax)
	}
	// cdq
	// idiv ebx
	emit(0x99)
	emit(0xf7, 0xfb)
	if gen.reg > 2 {
		// remainder result is stored EAX
		gen_push(.eax)
		for i := gen.reg - 2; i >= 0; i -= 1 {
			gen_pop(regs[i])
		}
	}
	gen.reg -= 1
}
gen_mod :: proc() {
	if gen.reg > 2 {
		for i in 0..<gen.reg {
			gen_push(regs[i])
		}
		gen_pop(.ebx)
		gen_pop(.eax)
	}

	// cdq
	// idiv ebx
	emit(0x99)
	emit(0xf7, 0xfb)
	if gen.reg > 2 {
		// remainder result is stored EDX
		gen_push(.edx)
		for i := gen.reg - 2; i >= 0; i -= 1 {
			gen_pop(regs[i])
		}
	}
	gen.reg -= 1
}

gen_call :: proc(p: ^Procedure) {
	call := p.addr - (gen.pc + 5)
	// call LOC
	emit(0xe8, splat(call))

}

gen_input :: proc(e: Entity) {
	if e.is_global {
		// push ADDR
		emit(0x68, splat(data_base + e.addr))
	} else {
		// lea REG, [esp+0x12]
		emit(0x8d, 0x84+u8(regs[gen.reg])*8, 0x24, splat(e.addr+12))
		gen_push(regs[gen.reg])
	}
	// push p_fmt_addr
	// call DWORD PTR ds:imp_scanf
	// add esp, 0x8
	emit(0x68, splat(p_fmt_addr))
	emit(0xff, 0x15, splat(imp_scanf))
	emit(0x83, 0xc4, 0x08)
}

gen_print :: proc() {
	gen.reg -= 1
	gen_push(regs[gen.reg])
	// push p_fmt_addr
	// call DWORD PTR ds:imp_printf
	// add esp, 0x8
	emit(0x68, splat(p_fmt_addr))
	emit(0xff, 0x15, splat(imp_printf))
	emit(0x83, 0xc4, 0x08)
}
