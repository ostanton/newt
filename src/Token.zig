/// Token for both the layout DSL and scripting language
kind: Kind,
value: []const u8,
line: usize,
column: usize,

pub const Kind = enum {
    ident,
    // 32-bit signed
    int_lit,
    // 32-bit,
    float_lit,
    string_lit,
    true_lit,
    false_lit,

    colon,
    comma,

    // Binary operators

    dot,
    assign,
    binding,
    plus,
    minus,
    star,
    slash,
    plus_assign,
    minus_assign,
    star_assign,
    slash_assign,
    greater_than,
    less_than,
    equal,
    not_equal,
    greater_equal,
    less_equal,
    not,

    left_bracket,
    right_bracket,
    left_square,
    right_square,
    left_brace,
    right_brace,

    // Keywords

    bool_type,
    float_type,
    int_type,
    string_type,
    func,
    @"enum",
    class,
    layout, // keyword for declaring layouts in script

    eof,
};
