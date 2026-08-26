package wasim

Tex_Range :: struct {
	start, end: Tex_Position,
}

Tex_Module :: struct {
	range: Tex_Range,
	id:    string,

	funcs: List(Tex_Func),
}

Tex_Value_Type_Node :: struct {
	next:       ^Tex_Value_Type_Node,
	value_type: Value_Type,
}

Tex_Param :: struct {
	next:       ^Tex_Param,
	id:         string,
	value_type: Value_Type,
}

// Indexs always have an index field, this is only guaranteed
// to be filled after the identifier resolving pass
Tex_Index :: struct {
	index: u32,
	id:    string,
}

Tex_Func_Type :: struct {
	params:  List(Tex_Param),
	results: List(Tex_Value_Type_Node),
}

Tex_Type_Use :: struct {
	using type_index: Tex_Index,
	inlined_type:     Tex_Func_Type,
}

Tex_Func :: struct {
	next:  ^Tex_Func,
	range: Tex_Range,
	id:    string,
	use:   Tex_Type_Use,
}
