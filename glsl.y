%start glsl-start

%%
    
glsl-start
    : translation_unit 'EOF'        { return new Program($1); }
    ;
        
variable_identifier
    : 'IDENTIFIER' {        
        var dec = yy.symbolTable.findVariable($1);
        if (!dec)
            error("Undeclared identifier", $1);
            
        // make sure this is a variable or function parameter
        if (!(dec instanceof VariableDeclarator || dec instanceof Identifier))
            error("Variable expected, found " + $1);
        
        $$ = new Identifier(dec.id ? dec.id.name : dec.name, dec.typeof, dec.arraySize);
    }
    ;
        
primary_expression
	: variable_identifier                     { $$ = $1; }
	| 'INTCONSTANT'                           { $$ = new Literal($1, 'int'); }
	| 'FLOATCONSTANT'                         { $$ = new Literal($1, 'float'); }
	| 'BOOLCONSTANT'                          { $$ = new Literal($1, 'bool'); }
	| 'LEFT_PAREN' expression 'RIGHT_PAREN'   { $$ = $2; }
	;
        
postfix_expression
	: primary_expression                          { $$ = $1; }
	| postfix_expression 'LEFT_BRACKET' expression 'RIGHT_BRACKET' {
        if (!$1.isArray && !$1.isMatrix() && !$1.isVector())
            error("left of '[' is not of type array, matrix, or vector");
        
        if ($3.typeof !== 'int')
            error('integer expression required');
            
        var val = $3.toConstant();
        if (val !== null && (val < 0 || val >= $1.componentCount()))
            error('Array access out of bounds');
        
        $$ = new MemberExpression($1, $3, true);
        $$.typeof = $1.componentType();
    } 
	| function_call                               { $$ = $1; }
	| postfix_expression 'DOT' 'FIELD_SELECTION'  {
        if ($1.isArray)
            error('cannot apply dot operator to an array');
            
        var struct = yy.symbolTable.findType($1.typeof);
        if (struct) {
            if (!struct.fields[$3])
                error('unknown field in structure');
                
            $$ = new MemberExpression($1, new Identifier($3), false);
            $$.typeof = struct.fields[$3].typeof;
            return;
        }
            
        if ($3.length > 4)
            error('illegal vector field selection');
            
        var offsets = {
            x: 0, r: 0, s: 0,
            y: 1, g: 1, t: 1,
            z: 2, b: 2, p: 2,
            w: 3, a: 3, q: 3
        };
        
        var sets = {
            x: 'xyzw', y: 'xyzw', z: 'xyzw', w: 'xyzw',
            r: 'rgba', g: 'rgba', b: 'rgba', a: 'rgba',
            s: 'stpq', t: 'stpq', p: 'stpq', q: 'stpq'
        };
        
        var maxOffset = $1.componentCount();
        var swizzle = [];
        var set = null;
        
        for (var i = 0; i < $3.length; i++) {
            var offset = offsets[$3[i]];
            if (offset == null)
                error('illegal vector field selection');
                
            if (offset >= maxOffset)
                error('vector field selection out of range');
                
            if (!set)
                set = sets[$3[i]];
            
            if (sets[$3[i]] !== set)
                error('vector component fields not from the same set');
                
            swizzle.push(offsets[$3[i]]);
        }
        
        $$ = new Swizzle($1, swizzle);
        if (swizzle.length === 1) {
            $$ = $$.getComponent(0);
        }
    }
	| postfix_expression 'INC_OP'                 { $$ = UpdateExpression.create('++', $1); }
	| postfix_expression 'DEC_OP'                 { $$ = UpdateExpression.create('--', $1); }
	;
    
function_call
    : function_call_generic {
        if ($1.isConstructor) {
            var type = $1.callee.name;
            var struct = yy.symbolTable.findType(type);
            if (struct) {
                if ($1.arguments.length !== Object.keys(struct.fields).length)
                    error('Number of constructor parameters does not match the number of structure fields');
                    
                var properties = [];
                for (var key in struct.fields) {
                    var val = $1.arguments[properties.length];
                    if (val.typeof !== struct.fields[key].typeof)
                        error('Incorrect parameter type');
                        
                    // TODO: clone references
                    if (val instanceof Identifier || val instanceof MemberExpression) {
                        
                    }
                        
                    properties.push(new Property(new Identifier(key), val));
                }
                
                $$ = new ObjectExpression(struct.name, properties);
                return;
            }
            
            var counts = {
                'vec2':  2, 'vec3':  3, 'vec4':  4,
                'ivec2': 2, 'ivec3': 3, 'ivec4': 4,
                'bvec2': 2, 'bvec3': 3, 'bvec4': 4,
                'mat2':  4, 'mat3':  9, 'mat4': 16,
                'float': 1, 'int':   1, 'bool':  1
            };
            
            var expectedCount = counts[type];
            if (!expectedCount)
                error('Unsupported constructor');
                
            var ret = new ArrayExpression(type);
            var args = ret;
            var full = false;
            var length = 0;
            
            for (var i = 0; i < $1.arguments.length; i++) {
                if (full)
                    error('too many arguments');
                
                var arg = $1.arguments[i];
                if (arg.isArray)
                    error('Cannot construct from an array');
                
                var count = arg.componentCount();
                
                // if this is a scalar, just add it to the vector directly
                if (count === 1) {
                    args.elements.push(convertArg(type, arg));
                    length++;
                    
                // if the last argument is longer than required and isn't a direct variable reference
                // we need to slice it rather than copy arguments directly since there could be an update
                // involved that needs to touch all components, not just the ones we use
                } else if (count > expectedCount - length && !(arg instanceof Identifier)) {
                    var slice = new CallExpression(
                        new MemberExpression(arg, new Identifier('slice')),
                        [new Literal(0), new Literal(expectedCount - length)]
                    );
                    
                    if (args.elements.length > 0) {
                        ret = new CallExpression(
                            new MemberExpression(ret, new Identifier('concat')),
                            [slice]
                        );
                    } else {
                        ret = slice;
                    }
                    
                    ret.typeof = type;
                    length = expectedCount;
                    
                // if not, just copy the arguments over from the other vector
                } else {
                    count = Math.min(count, expectedCount - length);
                    for (var j = 0; j < count; j++) {
                        args.elements.push(arg.getComponent(j));
                    }
                    
                    length += count;
                }
                
                if (length >= expectedCount)
                    full = true;
            }
            
            if (length !== 1 && length < expectedCount)
                error('Not enough arguments for constructor');
                
            // if a single scalar was given, fill the rest of the elements with the same value
            if (length < expectedCount) {
                for (var i = 1; i < expectedCount; i++) {
                    args.elements.push(args.elements[0]);
                }
            }
            
            if (expectedCount === 1) {
                $$ = args.elements[0];
            } else {
                $$ = ret;
            }
        } else {
            var fn = yy.symbolTable.findFunction($1);
            if (!fn || !(fn instanceof FunctionDeclaration))
                error("No matching function", $1.callee.name, "found");
        
            $1.callee.name = fn.id.name;
            $1.typeof = fn.returnType;
            $$ = $1;
        }
    }
    ;
    
function_call_generic
	: function_call_header_with_parameters 'RIGHT_PAREN'  { $$ = $1; }
	| function_call_header_no_parameters 'RIGHT_PAREN'    { $$ = $1; }
	;

function_call_header_no_parameters
	: function_call_header 'VOID' { $$ = $1; }
	| function_call_header        { $$ = $1; }
	;

function_call_header_with_parameters
	: function_call_header assignment_expression                          { $1.arguments.push($2); $$ = $1; }
	| function_call_header_with_parameters 'COMMA' assignment_expression  { $1.arguments.push($3); $$ = $1; }
	;

/* Grammar Note: Constructors look like functions, but lexical analysis recognized most of them as
   keywords. They are now recognized through type_specifier.
*/
function_call_header
    : type_specifier_nonarray 'LEFT_PAREN'  { $$ = new CallExpression($1); $$.isConstructor = true; }
	| 'IDENTIFIER' 'LEFT_PAREN'             { $$ = new CallExpression($1); }
	;
    
unary_expression
	: postfix_expression                  { $$ = $1; }
	| 'INC_OP' unary_expression           { $$ = UpdateExpression.create('++', $2, true); }
	| 'DEC_OP' unary_expression           { $$ = UpdateExpression.create('--', $2, true); }
	| unary_operator unary_expression     { $$ = UnaryExpression.create($1, $2); }
	;

unary_operator
	: 'PLUS'  { $$ = '+'; }
	| 'DASH'  { $$ = '-'; }
	| 'BANG'  { $$ = '!'; }
    // | 'TILDE' { $$ = '~'; }
	;
        
multiplicative_expression
	: unary_expression                                       { $$ = $1; }
	| multiplicative_expression 'STAR' unary_expression      { $$ = BinaryExpression.create($1, '*', $3); }
	| multiplicative_expression 'SLASH' unary_expression     { $$ = BinaryExpression.create($1, '/', $3); }
    // | multiplicative_expression 'PERCENT' unary_expression   { $$ = BinaryExpression.create($1, '%', $3); }
	;

additive_expression
	: multiplicative_expression                              { $$ = $1; }
	| additive_expression 'PLUS' multiplicative_expression   { $$ = BinaryExpression.create($1, '+', $3); }
	| additive_expression 'DASH' multiplicative_expression   { $$ = BinaryExpression.create($1, '-', $3); }
	;

// TODO: check types!
// shift_expression
//     : additive_expression                                    { $$ = $1; }
//     | shift_expression 'LEFT_OP' additive_expression         { $$ = BinaryExpression.create($1, '<<', $3); }
//     | shift_expression 'RIGHT_OP' additive_expression        { $$ = BinaryExpression.create($1, '>>', $3); }
//     ;

relational_expression
    : additive_expression                                       { $$ = $1; }
	| relational_expression 'LEFT_ANGLE' additive_expression    { $$ = BinaryExpression.create($1, '<', $3); }
	| relational_expression 'RIGHT_ANGLE' additive_expression   { $$ = BinaryExpression.create($1, '>', $3); }
	| relational_expression 'LE_OP' additive_expression         { $$ = BinaryExpression.create($1, '<=', $3); }
	| relational_expression 'GE_OP' additive_expression         { $$ = BinaryExpression.create($1, '>=', $3); }
	;
        
equality_expression
	: relational_expression                                  { $$ = $1; }
	| equality_expression 'EQ_OP' relational_expression      { $$ = BinaryExpression.create($1, '===', $3); }
	| equality_expression 'NE_OP' relational_expression      { $$ = BinaryExpression.create($1, '!==', $3); }
	;

// and_expression
//     : equality_expression                                    { $$ = $1; }
//     | and_expression 'AMPERSAND' equality_expression         { $$ = BinaryExpression.create($1, '&', $3); }
//     ;
// 
// exclusive_or_expression
//     : and_expression                                         { $$ = $1; }
//     | exclusive_or_expression 'CARET' and_expression         { $$ = BinaryExpression.create($1, '^', $3); }
//     ;
// 
// inclusive_or_expression
//     : exclusive_or_expression                                          { $$ = $1; }
//     | inclusive_or_expression 'VERTICAL_BAR' exclusive_or_expression   { $$ = BinaryExpression.create($1, '|', $3); }
//     ;

logical_and_expression
	: equality_expression                                  { $$ = $1; }
	| logical_and_expression 'AND_OP' equality_expression  { $$ = new LogicalExpression($1, '&&', $3); }
	;

logical_xor_expression
	: logical_and_expression                                   { $$ = $1; }
	| logical_xor_expression 'XOR_OP' logical_and_expression   {
        if ($1.typeof !== 'bool' || $3.typeof !== 'bool')
            error('Logical expression requires boolean arguments');
            
        $$ = BinaryExpression.create($1, '!==', $3); 
    }
	;

logical_or_expression
	: logical_xor_expression                                   { $$ = $1; }
	| logical_or_expression 'OR_OP' logical_xor_expression     { $$ = new LogicalExpression($1, '||', $3); }
	;

conditional_expression
	: logical_or_expression   { $$ = $1; }
	| logical_or_expression 'QUESTION' expression 'COLON' assignment_expression {
	    $$ = new ConditionalExpression($1, $3, $5)
	}
	;

assignment_expression
	: conditional_expression  { $$ = $1; }
	| unary_expression assignment_operator assignment_expression { 
        $$ = AssignmentExpression.create($1, $2, $3); 
    }
	;

assignment_operator
	: 'EQUAL'         { $$ = '='; }
	| 'MUL_ASSIGN'    { $$ = '*='; }
	| 'DIV_ASSIGN'    { $$ = '/='; }
    // | 'MOD_ASSIGN'    { $$ = '%='; }
	| 'ADD_ASSIGN'    { $$ = '+='; }
	| 'SUB_ASSIGN'    { $$ = '-='; }
    // | 'LEFT_ASSIGN'   { $$ = '<<='; }
    // | 'RIGHT_ASSIGN'  { $$ = '>>='; } // TODO: check types
    // | 'AND_ASSIGN'    { $$ = '&='; }
    // | 'XOR_ASSIGN'    { $$ = '^='; }
    // | 'OR_ASSIGN'     { $$ = '|='; }
	;

expression
	: assignment_expression                       { $$ = $1; }
	| expression 'COMMA' assignment_expression    { $$ = new SequenceExpression([$1, $3]); }
	;

constant_expression
	: conditional_expression {
        var val = $1.toConstant();
        if (val == null)
            error('constant expression required');
            
        $$ = new Literal(val, $1.typeof);
    }
	;
        
declaration
    : function_prototype 'SEMICOLON'    { yy.symbolTable.popScope(); $$ = null; }
    | init_declarator_list 'SEMICOLON'  { $$ = $1; }
    | PRECISION precision_qualifier type_specifier_no_prec SEMICOLON
    ;
    
function_prototype
    : function_declarator 'RIGHT_PAREN' { 
        $$ = $1;
        
        yy.symbolTable.add($1);
        yy.symbolTable.pushScope();
        for (var i = 0; i < $1.params.length; i++) {
            yy.symbolTable.add($1.params[i]);
        }
    }
    ;
    
function_declarator
    : function_header                   { $$ = $1; }
    | function_header_with_parameters   { $$ = $1; }
    ;
    
function_header_with_parameters
    : function_header parameter_declaration {
        $$ = $1;
        $1.params.push($2);
    }
    | function_header_with_parameters 'COMMA' parameter_declaration {
        $$ = $1;
        $1.params.push($3);
    }
    ;
    
function_header
    : fully_specified_type 'IDENTIFIER' 'LEFT_PAREN' { 
        $$ = new FunctionDeclaration($1, $2);
        yy.fn = $$;
        yy.fnReturned = false;
    }
    ;
    
parameter_declarator
    : type_specifier 'IDENTIFIER' {
        if ($1 === 'void')
            error('Illegal use of type void');
            
        $$ = new Identifier($2, $1);
    }
    | type_specifier 'IDENTIFIER' 'LEFT_BRACKET' constant_expression 'RIGHT_BRACKET' {
        // TODO: Check that we can make an array out of this type
        $$ = new Identifier($2, $1);
    }
    ;
    
parameter_declaration
    // Type + name
    : type_qualifier parameter_qualifier parameter_declarator       { $$ = $3; }
    | parameter_qualifier parameter_declarator                      { $$ = $2; }
    
    // Only type
    | type_qualifier parameter_qualifier parameter_type_specifier   { $$ = $3; }
    | parameter_qualifier parameter_type_specifier                  { $$ = $2; }
    ;
    
parameter_qualifier
    :             { $$ = 'in'; }
    | 'IN_TOK'    { $$ = 'in'; }
    | 'OUT_TOK'   { $$ = 'out'; }
    | 'INOUT_TOK' { $$ = 'inout'; }
    ;
    
parameter_type_specifier
    : type_specifier { $$ = new Identifier(null, $1); }
    ;
    
init_declarator_list
    : fully_specified_type { $$ = null }
    | fully_specified_type single_declaration {
        if ($1 === 'void')
            error('Illegal use of type void');
        
        if ($2.init != null && $2.init.typeof !== $1)
            error('Left and right arguments are of differing types');
        
        $2.initDefault($1);
        $$ = new VariableDeclaration($1, [$2]);
    }
    | init_declarator_list 'COMMA' single_declaration {
        if ($3.init != null && $3.init.typeof !== $1.typeof)
            error('Left and right arguments are of differing types');
            
        $3.initDefault($1.typeof);
        $1.declarations.push($3);
        $$ = $1;
    }
    ;
    
single_declaration
    : 'IDENTIFIER' { 
        $$ = yy.symbolTable.add(new VariableDeclarator($1));
    }
    | 'IDENTIFIER' 'LEFT_BRACKET' 'RIGHT_BRACKET' { 
        error('unsized array declarations not supported');
    }
    | 'IDENTIFIER' 'LEFT_BRACKET' constant_expression 'RIGHT_BRACKET' {
        if ($3.typeof !== 'int')
            error('array size must be a constant integer expression');
            
        if ($3.value <= 0)
            error('array size must be a positive integer');
            
        // initialization happens later once we know the type
        $$ = yy.symbolTable.add(new VariableDeclarator($1, null, $3.value));
    }
    | 'IDENTIFIER' 'EQUAL' initializer {
        $$ = yy.symbolTable.add(new VariableDeclarator($1, $3)); 
    }
    | 'INVARIANT' 'IDENTIFIER' { throw 'TODO'; }
    ;
    
fully_specified_type
    : type_specifier                    { $$ = $1; }
    | type_qualifier type_specifier     { $$ = $2; } // TODO: error handling
    ;
    
// TODO: handle
type_qualifier
    : 'CONST_TOK'
    | 'ATTRIBUTE'           { yy.symbolTable.checkGlobal($1); }
    | 'VARYING'             { yy.symbolTable.checkGlobal($1); }
    | 'INVARIANT' 'VARYING' { yy.symbolTable.checkGlobal($1 + ' ' + $2); }
    | 'UNIFORM'             { yy.symbolTable.checkGlobal($1); }
    ;
    
type_specifier
    : type_specifier_no_prec                        { $$ = $1; }
    | precision_qualifier type_specifier_no_prec    { $$ = $2; }
    ;
    
precision_qualifier
    : 'HIGH_PRECISION'}
    | 'MEDIUM_PRECISION'
    | 'LOW_PRECISION'
    ;
    
type_specifier_no_prec
    : type_specifier_nonarray                                                       { $$ = $1; }
    | type_specifier_nonarray 'LEFT_BRACKET' constant_expression 'RIGHT_BRACKET'    { $$ = $1; }
    ;
    
type_specifier_nonarray
	: 'VOID'
	| 'FLOAT'
	| 'INT'
	| 'BOOL'
	| 'VEC2'
	| 'VEC3'
	| 'VEC4'
	| 'BVEC2'
	| 'BVEC3'
	| 'BVEC4'
	| 'IVEC2'
	| 'IVEC3'
	| 'IVEC4'
	| 'MAT2'
	| 'MAT3'
	| 'MAT4'
	| 'SAMPLER1D'
	| 'SAMPLER2D'
	| 'SAMPLER3D'
	| 'SAMPLERCUBE'
	| struct_specifier
    | 'TYPE_NAME'
	;

struct_specifier
    : 'STRUCT' 'IDENTIFIER' 'LEFT_BRACE' struct_declaration_list 'RIGHT_BRACE' {
        yy.symbolTable.add(new StructureDeclaration($2, $4));
        $$ = $2;
    }
    // | 'STRUCT' 'LEFT_BRACE' struct_declaration_list 'RIGHT_BRACE'
    ;
    
struct_declaration_list
    : struct_declaration {
        $$ = {};
        for (var i = 0; i < $1.declarations.length; i++) {
            var dec = $1.declarations[i];
            if ($$[dec.id.name])
                error('duplicate field name in structure');
                
            dec.typeof = $1.typeof;
            $$[dec.id.name] = dec;
        }
    }
    | struct_declaration_list struct_declaration {
        $$ = $1;
        
        for (var i = 0; i < $2.declarations.length; i++) {
            var dec = $2.declarations[i];
            if ($$[dec.id.name])
                error('duplicate field name in structure');
                
            dec.typeof = $2.typeof;
            $$[dec.id.name] = dec;
        }
        
    }
    ;
    
struct_declaration
    : type_specifier struct_declarator_list 'SEMICOLON' {
        if ($1 === 'void')
            error('Illegal use of type void');
        
        $$ = new VariableDeclaration($1, $2);
    }
    ;
    
struct_declarator_list
    : struct_declarator                                 { $$ = [$1]; }
    | struct_declarator_list 'COMMA' struct_declarator  { $1.push($3); $$ = $1; }
    ;
    
struct_declarator
    : 'IDENTIFIER'  { $$ = new VariableDeclarator($1); }
    | 'IDENTIFIER' 'LEFT_BRACKET' constant_expression 'RIGHT_BRACKET' {
        if ($3.typeof !== 'int')
            error('array size must be a constant integer expression');
            
        if ($3.value <= 0)
            error('array size must be a positive integer');
        
        $$ = new VariableDeclarator($1, null, $3.value);
    }
    ;
    
initializer
    : assignment_expression { $$ = $1; }
    ;
    
declaration_statement
    : declaration { $$ = $1; }
    ;

statement
    : compound_statement  { $$ = $1; }
    | simple_statement    { $$ = $1; }
    ;

simple_statement
    : declaration_statement { $$ = $1; }
    | expression_statement  { $$ = $1; }
    | selection_statement   { $$ = $1; }
    | iteration_statement   { $$ = $1; }
    | jump_statement        { $$ = $1; }
    ;
    
push_scope: /* special action to add push a scope to the symbol table */
    { yy.symbolTable.pushScope(true); }
    ;
    
compound_statement
    : 'LEFT_BRACE' 'RIGHT_BRACE' { $$ = new BlockStatement(); }
    | 'LEFT_BRACE' push_scope statement_list 'RIGHT_BRACE' { 
        yy.symbolTable.popScope();
        $$ = $3;
    }
    ;
    
statement_no_new_scope
    : compound_statement_no_new_scope { $$ = $1; }
    | simple_statement                { $$ = $1; }
    ;

statement_with_scope
    : push_scope compound_statement_no_new_scope { yy.symbolTable.popScope(); $$ = $2; }
    | push_scope simple_statement                { yy.symbolTable.popScope(); $$ = $2; }
    ;

compound_statement_no_new_scope
    // Statement that doesn't create a new scope, for selection_statement, iteration_statement
    : 'LEFT_BRACE' 'RIGHT_BRACE'                { $$ = new BlockStatement(); }
    | 'LEFT_BRACE' statement_list 'RIGHT_BRACE' { $$ = $2; }
    ;
    
statement_list
    : statement                     { $$ = new BlockStatement([$1]); }
    | statement_list statement      { $1.body.push($2); $$ = $1; }
    ;
    
expression_statement
    : 'SEMICOLON'
    | expression 'SEMICOLON'    { $$ = new ExpressionStatement($1); }
    ;
    
selection_statement
    : 'IF' 'LEFT_PAREN' expression 'RIGHT_PAREN' selection_rest_statement { 
        $$ = new IfStatement($3, $5.consequent, $5.alternate); 
    }
    ;
    
selection_rest_statement
    : statement_with_scope 'ELSE' statement_with_scope {
        $$ = {}
        $$.consequent = $1;
        $$.alternate = $3;
    }
    | statement_with_scope {
        $$ = {}
        $$.consequent = $1;
        $$.alternate = null;
    }
    ;

condition
    : expression {
        if ($1.typeof !== 'bool')
            error('Boolean expression expected');
            
        $$ = $1;
    }
    | fully_specified_type 'IDENTIFIER' 'EQUAL' initializer { 
        $$ = AssignmentExpression.create($2, '=', $4);
    }
    ;
    
in_loop: /* action to increase loop level */
    { yy.loopLevel++; }
    ;
    
iteration_statement
    : 'WHILE' 'LEFT_PAREN' push_scope condition 'RIGHT_PAREN' in_loop statement_no_new_scope {
        yy.loopLevel--;
        yy.symbolTable.popScope();
        $$ = new WhileStatement($4, $7);
    }
    | 'DO' in_loop statement_with_scope 'WHILE' 'LEFT_PAREN' expression 'RIGHT_PAREN' 'SEMICOLON' {
        yy.loopLevel--;
        $$ = new DoWhileStatement($6, $3);
    }
    | 'FOR' 'LEFT_PAREN' push_scope for_init_statement for_rest_statement 'RIGHT_PAREN' in_loop statement_no_new_scope {
        yy.loopLevel--;
        yy.symbolTable.popScope();
        $$ = new ForStatement($4, $5.test, $5.update, $8);
    }
    ;
    
for_init_statement
    : expression_statement  { $$ = $1; }
    | declaration_statement { $$ = $1; }
    ;
    
conditionopt
    : condition         { $$ = $1; }
    | /* May be null */ { $$ = null; }
    ;
    
for_rest_statement
    : conditionopt 'SEMICOLON' {
        $$ = {}
        $$.test = $1;
        $$.update = null;
    }
    | conditionopt 'SEMICOLON' expression {
        $$ = {}
        $$.test = $1;
        $$.update = $3;
    }
    ;
    
jump_statement
    : 'BREAK' 'SEMICOLON' { 
        if (yy.loopLevel <= 0)
            error('break statement only allowed inside loops');
            
        $$ = new BreakStatement();
    }
    | 'CONTINUE' 'SEMICOLON' {
        if (yy.loopLevel <= 0)
            error('continue statement only allowed inside loops');
            
        $$ = new ContinueStatement();
    }
    | 'RETURN' 'SEMICOLON' {
        if (yy.fn.returnType !== 'void')
            error('non-void function must return a value');
            
        $$ = new ReturnStatement();
    }
    | 'RETURN' expression 'SEMICOLON' {
        if (yy.fn.returnType === 'void')
            error('void function cannot return a value');
            
        yy.fnReturned = true;
        if (yy.fn.returnType !== $2.typeof)
            error('incorrect function return type');
            
        $$ = new ReturnStatement($2);
    }
    | 'DISCARD' 'SEMICOLON'             { throw 'TODO'; }
    ;

translation_unit
    : external_declaration                  { $$ = [$1]; }
    | translation_unit external_declaration { if ($2) $1.push($2); $$ = $1; }
    ;
    
external_declaration
    : function_definition   { $$ = $1; }
    | declaration           { $$ = $1; }
    ;
    
function_definition
    : function_prototype compound_statement_no_new_scope {
        if (yy.fn.returnType !== 'void' && !yy.fnReturned)
            error('non-void function must return a value');
        
        $1.body = $2;
        $$ = $1;
        yy.symbolTable.popScope();
    }
    ;
    
%%

function convertArg(type, arg) {
    switch (type) {
        case 'vec2':
        case 'vec3':
        case 'vec4':
        case 'mat2':
        case 'mat3':
        case 'mat4':
        case 'float':
            if (arg.typeof !== 'float' && arg.typeof !== 'int') {
                arg = new UnaryExpression('+', arg);
            }
            
            arg.typeof = 'float';
            return arg;
            
        case 'ivec2':
        case 'ivec3':
        case 'ivec4':
        case 'int':
            if (arg.typeof !== 'int') {
                arg = new BinaryExpression(arg, '|', new Literal(0, arg.typeof));
                arg.typeof = 'int';
            }
            
            return arg;
            
        case 'bvec2':
        case 'bvec3':
        case 'bvec4':
        case 'bool':
            if (arg.typeof !== 'bool') {
                // arg = new CallExpression('Boolean', false, [arg]);
                arg = new UnaryExpression('!', new UnaryExpression('!', arg));
                arg.typeof = 'bool';
            }
            
            return arg;
            
        default:
            error('unsupported construction');
    }
}