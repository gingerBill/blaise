package main

import "core:os"
import "core:fmt"

main :: proc() {
	exe_name := "blaise" if len(os.args) == 0 else os.args[0]
	if len(os.args) < 2 {
		fmt.eprintln("%s usage: <filename>", exe_name)
	}
	filename := os.args[1]
	compile(filename)

	// {
	// 	data, ok := os.read_entire_file("blaise.exe")
	// 	defer delete(data)
	// 	assert(ok)
	// 	pe_offset := (^u32)(&data[60])^
	// 	pe := (^PEFileHeader)(&data[pe_offset])
	// 	optional_header := (^OptionalHeader64)(&data[pe_offset + size_of(PEFileHeader)])
	// 	fmt.printf("%v\n", pe)
	// 	fmt.printf("%#v\n", optional_header)
	// }
}