

# The Imba parser is generated by [Jison](http://github.com/zaach/jison)
# from this grammar file. Jison is a bottom-up parser generator, similar in
# style to [Bison](http://www.gnu.org/software/bison), implemented in JavaScript.
# It can recognize [LALR(1), LR(0), SLR(1), and LR(1)](http://en.wikipedia.org/wiki/LR_grammar)
# type grammars. To create the Jison parser, we list the pattern to match
# on the left-hand side, and the action to take (usually the creation of syntax
# tree nodes) on the right. As the parser runs, it
# shifts tokens from our token stream, from left to right, and
# [attempts to match](http://en.wikipedia.org/wiki/Bottom-up_parsing)
# the token sequence against the rules below. When a match can be made, it
# reduces into the [nonterminal](http://en.wikipedia.org/wiki/Terminal_and_nonterminal_symbols)
# (the enclosing name at the top), and we proceed from there.
#
# If you run the `cake build:parser` command, Jison constructs a parse table
# from our rules and saves it into `lib/parser.js`.

# The only dependency is on the **Jison.Parser**.

var jison = require '../jison/jison'
var Parser = jison.Parser

# Jison DSL
# ---------

# Since we're going to be wrapped in a function by Jison in any case, if our
# action immediately returns a value, we can optimize by removing the function
# wrapper and just returning the value directly.
var unwrap = /^function\s*\(\)\s*\{\s*return\s*([\s\S]*);\s*\}/

# Our handy DSL for Jison grammar generation, thanks to
# [Tim Caswell](http://github.com/creationix). For every rule in the grammar,
# we pass the pattern-defining string, the action to run, and extra options,
# optionally. If no action is specified, we simply pass the value of the
# previous nonterminal.

var o = do |patternString, action, options|
	patternString = patternString.replace /\s{2,}/g, ' '
	var patternCount = patternString.split(' '):length

	return [patternString, '$$ = $1;', options] unless action

	if var match = unwrap.exec(action)
		action = match[1]
	else 
		action = "({action}())"

	action = action.replace /\bA(\d+)/g, '$$$1'
	action = action.replace /\bnew /g, '$&yy.'
	action = action.replace /\b(?:Block\.wrap|extend)\b/g, 'yy.$&'
	action = action.replace /\bAST\b/g, 'yy'

	# really?
	# # should we always add locdata? does not work when statement)!
	# return [patternString, "$$ = #{loc(1, patternCount)}(#{action});", options]
	[patternString, "$$ = {action};", options]

# Grammatical Rules
# -----------------

# In all of the rules that follow, you'll see the name of the nonterminal as
# the key to a list of alternative matches. With each match's action, the
# dollar-sign variables are provided by Jison as references to the value of
# their numeric position, so in this rule:
#
#     "Expression UNLESS Expression"
#
# `A1` would be the value of the first `Expression`, `A2` would be the token
# for the `UNLESS` terminal, and `A3` would be the value of the second
# `Expression`.
var grammar =

	# The **Root** is the top-level node in the syntax tree. Since we parse bottom-up,
	# all parsing must end here.
	Root: [
		o '' do Root.new([])
		o 'Body' do Root.new(A1)
		o 'Block TERMINATOR'
	]

	# Any list of statements and expressions, separated by line breaks or semicolons.
	Body: [
		o 'BODYSTART' do Block.new([])
		o 'Line' do Block.new([A1])
		# o 'HEADER Line' do Block.new([A2])
		# o 'LeadingTerminator' do Block.new([Terminator.new(A1)])
		o 'Body Terminator Line' do A1.break(A2).add(A3) # A3.prebreak(A2) # why not add as real nodes?!
		o 'Body Terminator' do A1.break(A2)
	]

	Terminator: [
		o 'TERMINATOR' do Terminator.new(A1)
	]

	# An indented block of expressions. Note that the [Rewriter](rewriter.html)
	# will convert some postfix forms into blocks for us, by adjusting the
	# token stream.
	Block: [
		o 'INDENT OUTDENT' do Block.new([]).indented(A1,A2)
		o 'INDENT Body OUTDENT' do A2.indented(A1,A3)
		# hacky way to support terminators at the start of blocks
		o 'INDENT TERMINATOR Body OUTDENT' do A3.prebreak(A2).indented(A1,A4)
	]

	# Block and statements, which make up a line in a body.
	Line: [
		o 'Splat'
		o 'Expression'
		# o 'HEADER' do Terminator.new(A1)
		o 'Line , Expression' do A1.addExpression(A3) # Onto something??
		o 'Line , Splat' do A1.addExpression(A3) # Onto something?? # why is not splat an expression?
		o 'Comment'
		o 'Statement'
	]

	# Pure statements which cannot be expressions.
	Statement: [
		o 'Return'
		o 'Throw'
		o 'STATEMENT' do Literal.new A1

		o 'BREAK' do BreakStatement.new A1
		o 'BREAK CALL_START Expression CALL_END' do BreakStatement.new A1,A3

		o 'CONTINUE' do ContinueStatement.new A1
		o 'CONTINUE CALL_START Expression CALL_END' do ContinueStatement.new A1,A3

		o 'DEBUGGER' do DebuggerStatement.new A1
		o 'ImportStatement'
	]

	ImportStatement: [
		o 'IMPORT ImportArgList FROM ImportFrom' do ImportStatement.new(A2,A4)
		o 'IMPORT ImportFrom AS ImportArg' do ImportStatement.new(null,A2,A4)
		o 'IMPORT ImportFrom' do ImportStatement.new(null,A2)
	]

	ImportFrom: [
		o 'STRING'
	]

	ImportArgList: [
		o 'ImportArg' do [A1]
		o 'ImportArgList , ImportArg' do A1.concat A3
	]

	# Valid arguments are Blocks or Splats.
	ImportArg: [
		o 'VarIdentifier'
	]

	# All the different types of expressions in our language. The basic unit of
	# Imba is the **Expression** -- everything that can be an expression
	# is one. Blocks serve as the building blocks of many other rules, making
	# them somewhat circular.
	Expression: [
		o 'Await'
		o 'Value'
		o 'Code'
		o 'Operation'
		o 'Assign'
		o 'If'
		o 'Ternary'
		o 'Try'
		o 'While'
		o 'For'
		o 'Switch'
		o 'Class' # statement, no?
		o 'Module'
		o 'TagDeclaration'
		o 'Tag'
		o 'Property'
	]

	# A literal identifier, a variable name or property.
	Identifier: [
		o 'IDENTIFIER' do Identifier.new A1
	]

	# A literal identifier, a variable name or property.
	Ivar: [
		o 'IVAR' do Ivar.new A1
		o 'CVAR' do Ivar.new A1 # kinda hacky, should be defined as something else
	]

	Gvar: [
		o 'GVAR' do Gvar.new A1
	]

	Const: [
		o 'CONST' do Const.new A1
	]

	Argvar: [
		o 'ARGVAR' do Argvar.new A1
	]

	Symbol: [
		o 'SYMBOL' do Symbol.new A1
	]


	# Alphanumerics are separated from the other **Literal** matchers because
	# they can also serve as keys in object literals.
	AlphaNumeric: [
		o 'NUMBER' do Num.new A1
		o 'STRING' do Str.new A1
		o 'Symbol'
		o 'InterpolatedString'
	]

	InterpolatedString: [
		o 'STRING_START' do InterpolatedString.new([],open: A1)
		o 'InterpolatedString NEOSTRING' do A1.add A2
		o 'InterpolatedString Interpolation' do A2 ? A1.add(A2) : A1
		o 'InterpolatedString STRING_END' do A1.option('close',A2)
	]

	# The list of arguments to a function call.
	Interpolation: [
		o '{{ }}' do null
		o '{{ Expression }}' do A2
	]

	# All of our immediate values. Generally these can be passed straight
	# through and printed to JavaScript.
	Literal: [
		o 'AlphaNumeric'
		o 'JS' do Literal.new A1
		o 'REGEX' do RegExp.new A1
		o 'BOOL' do Bool.new A1
		o 'TRUE' do True.new(A1) # AST.TRUE # should not cheat like this
		o 'FALSE' do False.new(A1) # AST.FALSE
		o 'NULL' do Nil.new(A1) # AST.NIL
		o 'UNDEFINED' do Undefined.new(A1) # AST.UNDEFINED
		# we loose locations for these
	]

	# A return statement from a function body.
	Return: [
		o 'RETURN Expression' do Return.new A2
		o 'RETURN Arguments' do Return.new A2 # should probably force as array
		o 'RETURN' do Return.new
	]

	TagSelector: [
		o 'SELECTOR_START' do Selector.new([],type: A1)
		o 'TagSelector TagSelectorType' do A1.add SelectorType.new(A2), 'tag'
		o 'TagSelector SELECTOR_NS' do A1.add SelectorNamespace.new(A2), 'ns'
		o 'TagSelector SELECTOR_ID' do A1.add SelectorId.new(A2), 'id'
		o 'TagSelector SELECTOR_CLASS' do A1.add SelectorClass.new(A2), 'class'
		o 'TagSelector . { Expression }' do A1.add SelectorClass.new(A4), 'class'
		o 'TagSelector # { Expression }' do A1.add SelectorId.new(A4), 'id'
		o 'TagSelector SELECTOR_COMBINATOR' do A1.add SelectorCombinator.new(A2), 'sep'
		o 'TagSelector SELECTOR_PSEUDO_CLASS' do A1.add SelectorPseudoClass.new(A2), 'pseudoclass'
		o 'TagSelector SELECTOR_GROUP' do A1.group()
		o 'TagSelector UNIVERSAL_SELECTOR' do A1.add SelectorUniversal.new(A2), 'universal'
		o 'TagSelector [ Identifier ]' do A1.add SelectorAttribute.new(A3), 'attr'
		o 'TagSelector [ Identifier SELECTOR_ATTR_OP TagSelectorAttrValue ]' do
			A1.add SelectorAttribute.new(A3,A4,A5), 'attr'
	]

	TagSelectorType: [
		o 'SELECTOR_TAG' do TagTypeIdentifier.new(A1)
	]

	Selector: [
		o 'TagSelector SELECTOR_END' do A1
	]

	TagSelectorAttrValue: [
		o 'IDENTIFIER' do A1
		o 'AlphaNumeric' do A1
		o '{ Expression }' do A2
	]

	Tag: [
		o 'TAG_START TagOptions TAG_END' do A2.set(open: A1, close: A3)
		o 'TAG_START TagOptions TAG_END TagBody' do A2.set(body: A4, open: A1, close: A3)
		o 'TAG_START { Expression } TAG_END' do TagWrapper.new A3, A1, A5
	]

	TagTypeName: [
		o 'Self' do A1
		o 'IDENTIFIER' do TagTypeIdentifier.new(A1)
		o 'TAG_TYPE' do TagTypeIdentifier.new(A1)
		o '' do TagTypeIdentifier.new('div')
	]

	TagOptions: [
		o 'TagTypeName' do Tag.new(type: A1)
		o 'TagOptions . SYMBOL' do A1.addSymbol(A3)
		# o 'IDENTIFIER' do Tag.new(type: TagTypeIdentifier.new(A1))
		o 'TagOptions INDEX_START Expression INDEX_END' do A1.addIndex(A3)
		o 'TagOptions . IDENTIFIER' do A1.addClass(A3)
		o 'TagOptions . CONST' do A1.addClass(A3)
		o 'TagOptions . { Expression }' do A1.addClass(A4)
		o 'TagOptions @ { Expression }' do A1.set(key: A4)
		o 'TagOptions # IDENTIFIER' do A1.set(id: A3)
		o 'TagOptions Ivar' do A1.set(ivar: A2)
		o 'TagOptions # { Expression }' do A1.set(id: A4) # need to add info about the tokens
		o 'TagOptions TagAttr' do A1.addAttribute(A2) # need to add info about the tokens
	]


	TagAttributes: [
		o '' do []
		o 'TagAttr' do [A1]
		o 'TagAttributes , TagAttr' do A1.concat(A3)
		o 'TagAttributes OptComma TERMINATOR TagAttr' do A1.concat(A4)
	]

	TagAttr: [
		o 'TAG_ATTR' do TagAttr.new(A1,A1)
		o 'TAG_ATTR = TagAttrValue' do TagAttr.new(A1,A3,A2)
	]

	TagAttrValue: [
		# o 'Expression'
		o 'VALUE_START Expression VALUE_END' do A2
	]

	TagBody: [
		o 'INDENT ArgList OUTDENT' do A2.indented(A1,A3)
		# o 'ArgList' do A1
		o 'CALL_START ArgList CALL_END' do A2
	]

	TagTypeDef: [
		o 'Identifier' do TagDesc.new(A1)
		o 'TagTypeDef . Identifier' do A1.classes(A3)
	]
	
	

	# Class definitions have optional bodies of prototype property assignments,
	# and optional references to the superclass.
	TagDeclaration: [
		o 'TagDeclarationBlock' do A1
		o 'EXTEND TagDeclarationBlock' do A2.set(extension: yes)
		o 'LOCAL TagDeclarationBlock' do A2.set(local: yes)
		o 'EXPORT TagDeclarationBlock' do A2.set(export: A1)
		o 'GLOBAL TagDeclarationBlock' do A2.set(global: A1)
		o 'EXPORT GLOBAL TagDeclarationBlock' do A3.set(global: A1, export: A2)

	]

	TagDeclarationBlock: [
		o 'TAG TagType' do TagDeclaration.new(A2).set(keyword: A1)
		o 'TAG TagType Block' do TagDeclaration.new(A2, null, A3).set(keyword: A1)
		o 'TAG TagType COMPARE TagType' do TagDeclaration.new(A2, A4).set(keyword: A1)
		o 'TAG TagType COMPARE TagType Block' do TagDeclaration.new(A2, A4, A5).set(keyword: A1)
	]

	TagDeclKeywords: [
		o ''
		o 'EXTEND' do ['extend']
	]

	# Going to move back to fewer custom tokens
	TagType: [
		o 'TAG_TYPE' do TagTypeIdentifier.new(A1)
		o 'TAG_ID' do TagTypeIdentifier.new(A1)
	]

	
	TagId: [
		o 'IDREF' do TagId.new(A1)
		o '# Identifier' do TagId.new(A2)
	]

	

	# Assignment of a variable, property, or index to a value.
	Assign: [
		# o 'SimpleAssignable , Assign' do A3
		o 'Assignable = Expression' do Assign.new A2, A1, A3
		o 'Assignable = INDENT Expression Outdent' do Assign.new A2, A1, A4.indented(A3,A5)
	]

	# Assignment when it happens within an object literal. The difference from
	# the ordinary **Assign** is that these allow numbers and strings as keys.
	AssignObj: [
		o 'ObjAssignable' do ObjAttr.new A1
		o 'ObjAssignable : Expression' do ObjAttr.new A1, A3, 'object'
		o 'ObjAssignable : INDENT Expression Outdent' do ObjAttr.new A1, A4.indented(A3,A5), 'object'
		o 'Comment'
	]

	ObjAssignable: [
		o 'Identifier'
		o 'Const'
		o 'AlphaNumeric'
		o 'Ivar' # rly?
		o 'Gvar' # rly?
		# this is the interpolated string
		o '( Expression )' do A2
	]

	

	# A block comment.
	Comment: [
		o 'HERECOMMENT' do Comment.new A1,true
		o 'COMMENT' do Comment.new A1,false
	]

	# The **Code** node is the function literal. It's defined by an indented block
	# of **Block** preceded by a function arrow, with an optional parameter
	# list.
	Code: [
		o 'Method'
		o 'Do'
		o 'Begin'
	]

	Begin: [
		o 'BEGIN Block' do Begin.new A2
	]

	Do: [
		o 'DO Block' do Lambda.new [], A2, null,null, {bound: true, keyword: A1}
		o 'DO BLOCK_PARAM_START ParamList BLOCK_PARAM_END Block' do Lambda.new A3, A5, null, null, {bound: true, keyword: A1}
	]

	Property: [
		o 'PropType PropertyIdentifier Object' do PropertyDeclaration.new A2, A3, A1
		o 'PropType PropertyIdentifier CALL_START Object CALL_END' do PropertyDeclaration.new A2, A4, A1
		o 'PropType PropertyIdentifier' do PropertyDeclaration.new A2, null, A1
	]

	PropType: [
		o 'PROP'
		o 'ATTR'
	]

	PropertyIdentifier: [
		o 'Identifier'
		o '{ Expression }' do A2
	]

	TupleAssign: [
		# what about LET?
		o 'VAR Identifier , Expression' do A1
	]

	# FIXME clean up method
	Method: [
		o 'MethodDeclaration' do A1
		o 'GLOBAL MethodDeclaration' do A2.set(global: A1)
		o 'EXPORT MethodDeclaration' do A2.set(export: A1)
	]

	MethodDeclaration: [
		o 'DEF MethodScope MethodScopeType MethodIdentifier CALL_START ParamList CALL_END MethodBody' do
			MethodDeclaration.new(A6, A8, A4, A2, A3).set(def: A1)

		o 'DEF MethodScope MethodScopeType MethodIdentifier MethodBody' do
			MethodDeclaration.new([], A5, A4, A2, A3).set(def: A1)

		o 'DEF MethodIdentifier CALL_START ParamList CALL_END MethodBody' do
			MethodDeclaration.new(A4, A6, A2, null).set(def: A1)

		o 'DEF MethodIdentifier MethodBody' do
			MethodDeclaration.new([], A3, A2, null).set(def: A1)
	]

	MethodScopeType: [
		o '.' do {static: true}
		o '#' do {}
	] 

	MethodIdentifier: [
		o 'Identifier'
		o 'Const'
		o '{ Expression }' do A2
	]

	MethodReceiver: [

	]

	MethodBody: [
		o 'DEF_BODY Block' do A2
		o 'DEF_BODY Do' do A2.body
		o 'DEF_EMPTY' do []
	]

	# should support much more
	MethodScope: [
		o 'MethodIdentifier'
		o 'This'
		o 'Self' # global?
		o 'Gvar'
	]

	# An optional, trailing comma.
	OptComma: [
		o ''
		o ','
	]

	# The list of parameters that a function accepts can be of any length.
	ParamList: [
		o '' do []
		o 'Param' do [A1]
		o 'ParamList , Param' do A1.concat A3
	]

	# A single parameter in a function definition can be ordinary, or a splat
	# that hoovers up the remaining arguments.
	Param: [
		o 'Object' do NamedParams.new(A1)
		o 'Array' do ArrayParams.new(A1)
		o 'ParamVar' do RequiredParam.new A1
		o 'SPLAT ParamVar' do SplatParam.new A2, null, A1
		o 'LOGIC ParamVar' do BlockParam.new A2, null, A1
		o 'BLOCK_ARG ParamVar' do BlockParam.new A2, null, A1
		o 'ParamVar = Expression' do OptionalParam.new A1, A3, A2
	]

	# Function Parameters
	ParamVar: [
		o 'Identifier'
	]

	# A splat that occurs outside of a parameter list.
	Splat: [
		o 'SPLAT Expression' do AST.SPLAT(A2)
	]

	VarReference: [
		o 'VAR SPLAT VarAssignable' do AST.SPLAT(VarReference.new(A3,A1),A2) # LocalIdentifier.new(A1)
		o 'VAR VarAssignable' do VarReference.new(A2,A1) # LocalIdentifier.new(A1)
		o 'LET VarAssignable' do VarReference.new(A2,A1) # LocalIdentifier.new(A1)
		o 'LET SPLAT VarAssignable' do AST.SPLAT(VarReference.new(A3,A1),A2) # LocalIdentifier.new(A1)
		o 'EXPORT VarReference' do A2.set(export: A1)
	]

	VarIdentifier: [
		o 'Const'
		o 'Identifier'
	]

	VarAssignable: [
		o 'Const'
		o 'Identifier'
		o 'Array' # all kinds?
	]

	# Variables and properties that can be assigned to.
	SimpleAssignable: [
		o 'ENV_FLAG' do EnvFlag.new(A1)
		o 'Const'
		o 'Ivar' do IvarAccess.new('.',null,A1)
		o 'Gvar'
		o 'Argvar'
		o 'Self' # not sure if self should be assignable really
		o 'VarReference'
		o 'Identifier' do VarOrAccess.new(A1) # LocalIdentifier.new(A1)
		o 'Value . NEW' do New.new(A1)
		o 'Value . Super' do SuperAccess.new('.',A1,A3)
		o 'Value SoakableOp Identifier' do PropertyAccess.new(A2,A1,A3)
		o 'Value ?: Identifier' do Access.new(A2,A1,A3)
		o 'Value .: Identifier' do Access.new(A2,A1,A3)
		o 'Value SoakableOp Ivar' do Access.new(A2,A1,A3)
		o 'Value . Symbol' do Access.new('.',A1,Identifier.new(A3.value))
		o 'Value SoakableOp Const' do Access.new(A2,A1,A3)
		o 'Value INDEX_START IndexValue INDEX_END' do IndexAccess.new('.',A1,A3)
	]

	SoakableOp: [
		'.'
		'?.'
	]

	Super: [
		o 'SUPER' do AST.SUPER
	]

	# Everything that can be assigned to.
	Assignable: [
		o 'SimpleAssignable'
		o 'Array' #  do A1
		o 'Object' # not supported anymore
	]

	Await: [
		o 'AWAIT Expression' do Await.new(A2).set(keyword: A1)
	]

	# The types of things that can be treated as values -- assigned to, invoked
	# as functions, indexed into, named as a class, etc.
	Value: [
		o 'Assignable'
		o 'Super'
		o 'Literal'
		o 'Parenthetical'
		o 'Range'
		o 'ARGUMENTS' do AST.ARGUMENTS
		o 'This'
		o 'TagId'
		o 'Selector'
		o 'Invocation'
	]

	IndexValue: [
		# Do we need to wrap this?
		o 'Expression' do Index.new A1
		o 'Slice' do Slice.new A1
	]

	# In Imba, an object literal is simply a list of assignments.
	Object: [
		o '{ AssignList OptComma }' do Obj.new A2, A1:generated
	]

	# Assignment of properties within an object literal can be separated by
	# comma, as in JavaScript, or simply by newline.
	AssignList: [
		o '' do AssignList.new([])
		o 'AssignObj' do AssignList.new([A1])
		o 'AssignList , AssignObj' do A1.add A3
		o 'AssignList OptComma Terminator AssignObj' do A1.add(A3).add(A4) # A4.prebreak(A3)
		# this is strange
		o 'AssignList OptComma INDENT AssignList OptComma Outdent' do  A1.concat(A4.indented(A3,A6))
	]

	# Class definitions have optional bodies of prototype property assignments,
	# and optional references to the superclass.


	# might as well handle this in the lexer instead
	Class: [
		o 'ClassStart' do A1
		o 'EXTEND ClassStart' do A2.set(extension: A1)
		o 'LOCAL ClassStart' do A2.set(local: A1)
		o 'GLOBAL ClassStart' do A2.set(global: A1)
		o 'EXPORT ClassStart' do A2.set(export: A1)
		o 'EXPORT LOCAL ClassStart' do A3.set(export: A1, local: A2)
	]

	ClassStart: [
		o 'CLASS SimpleAssignable' do ClassDeclaration.new(A2, null, []).set(keyword: A1)
		o 'CLASS SimpleAssignable Block' do ClassDeclaration.new(A2, null, A3).set(keyword: A1)
		o 'CLASS SimpleAssignable COMPARE Expression' do ClassDeclaration.new(A2, A4, []).set(keyword: A1)
		o 'CLASS SimpleAssignable COMPARE Expression Block' do ClassDeclaration.new(A2, A4, A5).set(keyword: A1)
	]

	# should be removed - not used
	Module: [
		o 'MODULE SimpleAssignable' do Module.new A2
		o 'MODULE SimpleAssignable Block' do Module.new A2, null, A3
	]

	# Ordinary function invocation, or a chained series of calls.
	Invocation: [
		o 'Value OptFuncExist Arguments' do Call.new A1, A3, A2
		o 'Value Do' do A1.addBlock(A2)
	]

	# An optional existence check on a function.
	OptFuncExist: [
		o '' do no
		o 'FUNC_EXIST' do yes
	]

	# The list of arguments to a function call.
	Arguments: [
		o 'CALL_START CALL_END' do ArgList.new([])
		o 'CALL_START ArgList OptComma CALL_END' do A2
	]

	# A reference to the *this* current object.
	This: [
		o 'THIS' do This.new(A1) # Value.new Literal.new 'this'
	]

	Self: [
		o 'SELF' do Self.new(A1)
	]

	# The array literal.
	Array: [
		o '[ ]' do Arr.new ArgList.new([])
		o '[ ArgList OptComma ]' do Arr.new A2
	]

	# Inclusive and exclusive range dots.
	# should return the tokens instead
	RangeDots: [
		o '..' do '..'
		o '...' do '...'
	]

	Range: [
		o '[ Expression RangeDots Expression ]' do AST.OP(A3,A2,A4) # Range.new A2, A4, A3
	]

	# Array slice literals.
	Slice: [
		o 'Expression RangeDots Expression' do Range.new A1, A3, A2
		o 'Expression RangeDots' do Range.new A1, null, A2
		o 'RangeDots Expression' do Range.new null, A2, A1
	]

	# The **ArgList** is both the list of objects passed into a function call,
	# as well as the contents of an array literal
	# (i.e. comma-separated expressions). Newlines work as well.
	ArgList: [
		o 'Arg' do ArgList.new([A1])
		o 'ArgList , Arg' do A1.add A3
		o 'ArgList OptComma Terminator Arg' do A1.add(A3).add(A4)
		o 'INDENT ArgList OptComma Outdent' do A2.indented(A1,A4)
		o 'ArgList OptComma INDENT ArgList OptComma Outdent' do A1.concat A4
	]

	Outdent: [
		o 'Terminator OUTDENT' do A1 # we are going to change how this works
		o 'OUTDENT' do A1
	]

	# Valid arguments are Blocks or Splats.
	Arg: [
		o 'Expression'
		o 'Splat'
		o 'LOGIC'
		o 'Comment'
	]

	# Just simple, comma-separated, required arguments (no fancy syntax). We need
	# this to be separate from the **ArgList** for use in **Switch** blocks, where
	# having the newlines wouldn't make sense.
	SimpleArgs: [
		o 'Expression'
		o 'SimpleArgs , Expression' do [].concat A1, A3
	]

	# The variants of *try/catch/finally* exception handling blocks.
	Try: [
		o 'TRY Block' do Try.new A2
		o 'TRY Block Catch' do Try.new A2, A3
		o 'TRY Block Finally' do Try.new A2, null, A3
		o 'TRY Block Catch Finally' do Try.new A2, A3, A4
	]

	Finally: [
		o 'FINALLY Block' do Finally.new A2
	]

	# A catch clause names its error and runs a block of code.
	Catch: [
		o 'CATCH CATCH_VAR Block' do Catch.new(A3,A2)
		# o 'CATCH CATCH_VAR Expression' do Catch.new(A3,A2)
	]

	# Throw an exception object.
	Throw: [
		o 'THROW Expression' do Throw.new A2
	]

	# Parenthetical expressions. Note that the **Parenthetical** is a **Value**,
	# not an **Expression**, so if you need to use an expression in a place
	# where only values are accepted, wrapping it in parentheses will always do
	# the trick.
	Parenthetical: [
		o '( Body )' do Parens.new(A2,A1,A3)
		o '( INDENT Body OUTDENT )' do Parens.new(A3,A1,A5)
	]
	# The condition portion of a while loop.
	WhileSource: [
		o 'WHILE Expression' do While.new(A2, keyword: A1)
		o 'WHILE Expression WHEN Expression' do While.new(A2, guard: A4, keyword: A1)
		o 'UNTIL Expression' do While.new(A2, invert: true, keyword: A1)
		o 'UNTIL Expression WHEN Expression' do While.new(A2, invert: true, guard: A4, keyword: A1)
	]

	# The while loop can either be normal, with a block of expressions to execute,
	# or postfix, with a single expression. There is no do..while.
	# should be solved by POST_WHILE instead
	While: [
		o 'WhileSource Block' do A1.addBody A2
		o 'Statement  WhileSource' do A2.addBody Block.wrap [A1]
		o 'Expression WhileSource' do A2.addBody Block.wrap [A1]
		o 'Loop' do A1
	]

	# should deprecate
	Loop: [
		o 'LOOP Block' do While.new(Literal.new 'true', keyword: A1).addBody A2
		o 'LOOP Expression' do While.new(Literal.new 'true', keyword: A1).addBody Block.wrap [A2]
	]

	# Array, object, and range comprehensions, at the most generic level.
	# Comprehensions can either be normal, with a block of expressions to execute,
	# or postfix, with a single expression.
	For: [
		o 'Statement  ForBody' do A2.addBody([A1])
		o 'Expression ForBody' do A2.addBody([A1])
		o 'ForBody    Block' do A1.addBody(A2)
	]

	ForKeyword: [
		o 'FOR'
		o 'POST_FOR'
	]

	ForBlock: [
		o 'ForBody Block' do A1.addBody(A2)
	]

	ForBody: [
		o 'ForKeyword Range' do source: ValueNode.new(A2)
		o 'ForStart ForSource' do A2.configure(own: A1:own, name: A1[0], index: A1[1], keyword: A1:keyword)
	]

	ForStart: [
		o 'ForKeyword ForVariables' do (A2:keyword = A1) && A2

		# should link to the actual keyword instead
		o 'ForKeyword OWN ForVariables' do (A3:own = yes) && (A3:keyword = A1) && A3

	]

	# An array of all accepted values for a variable inside the loop.
	# This enables support for pattern matching.
	ForValue: [
		o 'Identifier'
		o 'Array' do ValueNode.new A1
		o 'Object' do ValueNode.new A1
	]

	# An array or range comprehension has variables for the current element
	# and (optional) reference to the current index. Or, *key, value*, in the case
	# of object comprehensions.
	ForVariables: [
		o 'ForValue' do [A1]
		o 'ForValue , ForValue' do [A1, A3]
	]

	# The source of a comprehension is an array or object with an optional guard
	# clause. If it's an array comprehension, you can also choose to step through
	# in fixed-size increments.
	ForSource: [
		o 'FORIN Expression' do ForIn.new source: A2
		o 'FOROF Expression' do ForOf.new source: A2, object: yes
		o 'FORIN Expression WHEN Expression' do ForIn.new source: A2, guard: A4
		o 'FOROF Expression WHEN Expression' do ForOf.new source: A2, guard: A4, object: yes
		o 'FORIN Expression BY Expression' do ForIn.new source: A2, step:  A4
		o 'FORIN Expression WHEN Expression BY Expression' do ForIn.new source: A2, guard: A4, step: A6
		o 'FORIN Expression BY Expression WHEN Expression' do ForIn.new source: A2, step:  A4, guard: A6
	]

	Switch: [
		o 'SWITCH Expression INDENT Whens OUTDENT' do Switch.new A2, A4
		o 'SWITCH Expression INDENT Whens ELSE Block Outdent' do Switch.new A2, A4, A6
		o 'SWITCH INDENT Whens OUTDENT' do Switch.new null, A3
		o 'SWITCH INDENT Whens ELSE Block OUTDENT' do Switch.new null, A3, A5
	]

	Whens: [
		o 'When'
		o 'Whens When' do A1.concat A2
	]

	# An individual **When** clause, with action.
	When: [
		o 'LEADING_WHEN SimpleArgs Block' do [SwitchCase.new(A2, A3)]
		o 'LEADING_WHEN SimpleArgs Block TERMINATOR' do [SwitchCase.new(A2, A3)]
	]

	# The most basic form of *if* is a condition and an action. The following
	# if-related rules are broken up along these lines in order to avoid
	# ambiguity.


	IfBlock: [
		o 'IF Expression Block' do If.new(A2, A3, type: A1)
		o 'IfBlock ELSE IF Expression Block' do A1.addElse If.new(A4, A5, type: A3)

		# seems like this refers to the wrong blocks no?
		o 'IfBlock ELIF Expression Block' do 
			A1.addElse If.new(A3, A4, type: A2)

		o 'IfBlock ELSE Block' do A1.addElse A3
	]

	# The full complement of *if* expressions, including postfix one-liner
	# *if* and *unless*.
	If: [
		o 'IfBlock'
		o 'Statement  POST_IF Expression' do If.new A3, Block.new([A1]), type: A2, statement: true
		o 'Expression POST_IF Expression' do If.new A3, Block.new([A1]), type: A2 # , statement: true # why is this a statement?!?
	]

	Ternary: [
		o 'Expression ? Expression : Expression' do AST.If.ternary(A1,A3,A5)
	]

	# Arithmetic and logical operators, working on one or more operands.
	# Here they are grouped by order of precedence. The actual precedence rules
	# are defined at the bottom of the page. It would be shorter if we could
	# combine most of these rules into a single generic *Operand OpSymbol Operand*
	# -type rule, but in order to make the precedence binding possible, separate
	# rules are necessary.
	Operation: [
		o 'UNARY Expression' do AST.OP A1, A2
		o 'SQRT Expression' do AST.OP A1, A2
		o('-     Expression', &, prec: 'UNARY') do Op.new '-', A2
		o('+     Expression', &, prec: 'UNARY') do Op.new '+', A2
		o '-- SimpleAssignable' do UnaryOp.new '--', null, A2
		o '++ SimpleAssignable' do UnaryOp.new '++', null, A2
		o 'SimpleAssignable --' do UnaryOp.new '--', A1, null, true
		o 'SimpleAssignable ++' do UnaryOp.new '++', A1, null, true

		o 'Expression +  Expression' do Op.new(A2,A1,A3)
		o 'Expression -  Expression' do Op.new(A2,A1,A3)

		o 'Expression MATH     Expression' do AST.OP A2, A1, A3
		o 'Expression SHIFT    Expression' do AST.OP A2, A1, A3
		o 'Expression COMPARE  Expression' do AST.OP A2, A1, A3
		o 'Expression LOGIC    Expression' do AST.OP A2, A1, A3
		# o 'Expression ?.    Expression' do AST.OP A2, A1, A3

		o 'Expression RELATION Expression' do
			if A2.charAt(0) is '!'
				AST.OP(A2.slice(1), A1, A3).invert
			else
				AST.OP A2, A1, A3

		o 'SimpleAssignable COMPOUND_ASSIGN Expression' do AST.OP_COMPOUND(A2.@value,A2,A1,A3)
		o 'SimpleAssignable COMPOUND_ASSIGN INDENT Expression Outdent' do AST.OP_COMPOUND(A2.@value, A1, A4.indented(A3,A5))
	]


# Precedence
# ----------

var operators = [
	['left',      'MSET']
	['left',      '.', '?.', '?:', '::','.:']
	['left',      'CALL_START', 'CALL_END']
	# ['left',      '{{', '}}']
	# ['left', 'STRING_START','STRING_END']
	['nonassoc',  '++', '--']
	['right',     'UNARY','THROW','SQRT']
	['left',      'MATH']
	['left',      '+', '-']
	['left',      'SHIFT']
	['left',      'RELATION']
	['left',      'COMPARE']
	['left',      'LOGIC']
	['left',      '?']
	['left','AWAIT'] # not really sure?
	['nonassoc',  'INDENT', 'OUTDENT']
	['right',     '=', ':', 'COMPOUND_ASSIGN', 'RETURN', 'THROW', 'EXTENDS']
	['right',     'FORIN', 'FOROF', 'BY', 'WHEN']
	['right',     'TAG_END']
	['right',     'IF', 'ELSE', 'FOR', 'DO', 'WHILE', 'UNTIL', 'LOOP', 'SUPER', 'CLASS', 'MODULE', 'TAG', 'EVENT', 'TRIGGER', 'TAG_END']
	['right',     'POST_IF','POST_FOR']
	['right', 'NEW_TAG']
	['right', 'TAG_ATTR_SET']
	['right', 'SPLAT']
	['left', 'SELECTOR_START']
]

# Wrapping Up
# -----------

# Finally, now that we have our **grammar** and our **operators**, we can create
# our **Jison.Parser**. We do this by processing all of our rules, recording all
# terminals (every symbol which does not appear as the name of a rule above)
# as "tokens".

var tokens = []
for name, alternatives of grammar
	grammar[name] = for alt in alternatives
		for token in alt[0].split(' ')
			tokens.push token unless grammar[token]
		alt[1] = "return {alt[1]}" if name is 'Root'
		alt

# Initialize the **Parser** with our list of terminal **tokens**, our **grammar**
# rules, and the name of the root. Reverse the operators because Jison orders
# precedence from low to high, and we have it high to low
# (as in [Yacc](http://dinosaur.compilertools.net/yacc/index.html)).

exports:parser = Parser.new 
	tokens: tokens.join(' ')
	bnf: grammar
	operators: operators.reverse
	startSymbol: 'Root'

