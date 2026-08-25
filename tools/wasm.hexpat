// Enter your pattern code here and click on the Play button
// below to execute your code. The results will then be visible
// in the Pattern Data view.
// 
// More information can be found in the documentation.
// 
// 
// Simple example:
// 
// import std.io;
// 
// struct Pattern {
//     u32 int;
//     float floating_point;
// };
// 
// Pattern my_pattern @ 0x00;
// std::print("0x{:08X}", my_pattern.int);

import type.leb128;

using uLEB128 = type::uLEB128;

enum Section_Type : u8 {
    Custom,
    Type,
    Import,
    Function,
    Table,
    Memory,
    Global,
    Export,
    Start,
    Element,
    Code,
    Data,
};

struct String {
    uLEB128 size;
    char content[size];
};

enum Export_Type : u8 {
    Func,
    Table,
    Mem,
    Global,
};

struct Export {
    String name;
    Export_Type type;
    uLEB128 idx;
};

struct Section {
    Section_Type type;
    uLEB128 size;
    
    if (type == Section_Type::Export) {
        uLEB128 export_count;
        Export exports[export_count];
    } else {
        u8 data[size];
    }
};

struct File {
    char magic[4];
    u32  version;
    Section sections[while($ < sizeof($))];
};

File file @ 0;