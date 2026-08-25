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

Tex_Func :: struct {
	next:  ^Tex_Func,
	range: Tex_Range,
	id:    string,
}
