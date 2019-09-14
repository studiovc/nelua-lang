local cdefs = require 'nelua.cdefs'
local CEmitter = require 'nelua.cemitter'

local builtins = {}

local operators = {}
builtins.operators = operators

function operators.len(node, emitter, argnode)
  local type = argnode.attr.type
  if type:is_arraytable() then
    emitter:add(type, '_length(&', argnode, ')')
  elseif type:is_array() then
    emitter:add(type.length)
  elseif type:is_type() then
    emitter:add(argnode.attr.holdedtype.size)
  else --luacov:disable
    node:errorf('not implemented')
  end --luacov:enable
end

function operators.div(node, emitter, lnode, rnode, lname, rname)
  local type, ltype, rtype = node.attr.type, lnode.attr.type, rnode.attr.type
  if ltype:is_numeric() and rtype:is_numeric() then
    if not rtype:is_float() and not ltype:is_float() then
      assert(type:is_float())
      emitter:add(lname, ' / (', type, ')', rname)
    else
      emitter:add(lname, ' / ', rname)
    end
  else --luacov:disable
    node:errorf('not implemented')
  end --luacov:enable
end

function operators.idiv(node, emitter, lnode, rnode, lname, rname)
  local type, ltype, rtype = node.attr.type, lnode.attr.type, rnode.attr.type
  if ltype:is_numeric() and rtype:is_numeric() then
    if ltype:is_float() or rtype:is_float() then
      local floorname = type:is_float32() and 'floorf' or 'floor'
      emitter:add(floorname, '(', lname, ' / ', rname, ')')
      emitter.context.has_math = true
    else
      emitter:add(lname, ' / ', rname)
    end
  else --luacov:disable
    node:errorf('not implemented')
  end --luacov:enable
end

function operators.mod(node, emitter, lnode, rnode, lname, rname)
  local type, ltype, rtype = node.attr.type, lnode.attr.type, rnode.attr.type
  if ltype:is_numeric() and rtype:is_numeric() then
    if ltype:is_float() or rtype:is_float() then
      local modfuncname = type:is_float32() and 'fmodf' or 'fmod'
      emitter:add(modfuncname, '(', lname, ', ', rname, ')')
      emitter.context.has_math = true
    else
      emitter:add(lname, ' % ', rname)
    end
  else --luacov:disable
    node:errorf('not implemented')
  end --luacov:enable
end

function operators.pow(node, emitter, lnode, rnode, lname, rname)
  local type, ltype, rtype = node.attr.type, lnode.attr.type, rnode.attr.type
  if ltype:is_numeric() and rtype:is_numeric() then
    local powname = type:is_float32() and 'powf' or 'pow'
    emitter:add(powname, '(', lname, ', ', rname, ')')
    emitter.context.has_math = true
  else --luacov:disable
    node:errorf('not implemented')
  end --luacov:enable
end

function operators.eq(_, emitter, lnode, rnode, lname, rname)
  local ltype, rtype = lnode.attr.type, rnode.attr.type
  if ltype:is_string() and rtype:is_string() then
    emitter:add('nelua_string_eq(', lname, ', ', rname, ')')
  else
    emitter:add(lname, ' ', cdefs.compare_ops.eq, ' ', rname)
  end
end

function operators.ne(_, emitter, lnode, rnode, lname, rname)
  local ltype, rtype = lnode.attr.type, rnode.attr.type
  if ltype:is_string() and rtype:is_string() then
    emitter:add('nelua_string_ne(', lname, ', ', rname, ')')
  else
    emitter:add(lname, ' ', cdefs.compare_ops.ne, ' ', rname)
  end
end

function operators.range(node, emitter, lnode, rnode)
  local subtype = node.attr.type.subtype
  emitter:add_nodectypecast(node)
  emitter:add('{')
  emitter:add_val2type(subtype, lnode)
  emitter:add(',')
  emitter:add_val2type(subtype, rnode)
  emitter:add('}')
end

local functions = {}
builtins.functions = functions

function functions.assert(context, node)
  local args = node:args()
  if #args == 2 then
    context:add_runtime_builtin('assert_message')
    return 'nelua_assert_string'
  elseif #args == 1 then
    context:add_runtime_builtin('assert')
    return 'nelua_assert'
  else
    node:raisef('invalid assert call')
  end
end

function functions.print(context, node)
  local argnodes = node:args()
  local funcname = context:genuniquename('nelua_print')

  context:add_runtime_builtin('stdout_write')

  --function declaration
  local decemitter = CEmitter(context)
  decemitter:add_indent('static inline ')
  decemitter:add('void ', funcname, '(')
  for i,argnode in ipairs(argnodes) do
    if i>1 then decemitter:add(', ') end
    decemitter:add('const ', argnode.attr.type, ' a', i)
  end
  decemitter:add_ln(');')
  context:add_declaration(decemitter:generate(), funcname)

  --function head
  local defemitter = CEmitter(context)
  defemitter:add_indent('void ', funcname, '(')
  for i,argnode in ipairs(argnodes) do
    if i>1 then defemitter:add(', ') end
    defemitter:add('const ', argnode.attr.type, ' a', i)
  end
  defemitter:add(')')

  -- function body
  defemitter:add_ln(' {')
  defemitter:inc_indent()
  for i,argnode in ipairs(argnodes) do
    local argtype = argnode.attr.type
    if i > 1 then
      defemitter:add_indent_ln('nelua_stdout_write("\\t");')
    end
    if argtype:is_any() then
      defemitter:add_indent_ln('nelua_stdout_write_any(a',i,');')
    elseif argtype:is_string() then
      defemitter:add_indent_ln('nelua_stdout_write_string(a',i,');')
    elseif argtype:is_cstring() then
      defemitter:add_indent_ln('nelua_stdout_write(a',i,');')
    elseif argtype:is_boolean() then
      defemitter:add_indent_ln('nelua_stdout_write_boolean(a',i,');')
    elseif argtype:is_numeric() then
      local tyname = node:assertraisef(argtype, 'type is not defined in AST node')
      local tyformat = cdefs.types_printf_format[tyname]
      node:assertraisef(tyformat, 'invalid type "%s" for printf format', tyname)
      defemitter:add_indent_ln('nelua_stdout_write_format("',tyformat,'", a',i,');')
    else --luacov:disable
      node:raisef('cannot handle type "%s" in print', argtype)
    end --luacov:enable
  end
  defemitter:add_indent_ln('nelua_stdout_write_newline();')
  defemitter:dec_indent()
  defemitter:add_ln('}')

  context:add_definition(defemitter:generate(), funcname)

  -- the call
  return funcname
end

function functions.type(context, node, emitter)
  local argnode = node[1][1]
  local type = argnode.attr.type
  context:add_runtime_builtin('type_strings')
  local typename
  if type:is_numeric() then
    typename = 'number'
  elseif type:is_nilptr() then
    typename = 'pointer'
  elseif type:is_any() then --luacov:disable
    node:raisef('type() for any values not implemented yet')
  else --luacov:enable
    typename = type.name
  end
  emitter:add('&nelua_typestr_', typename)
  return nil
end

function functions.likely()
  return 'Nelua_LIKELY'
end

function functions.unlikely()
  return 'Nelua_UNLIKELY'
end

function functions.error()
  return 'nelua_panic_string'
end

function functions.warn()
  return 'nelua_stderr_write_string'
end

function functions.panic()
  return 'nelua_panic_string'
end

function functions.require(context, node, emitter)
  local scope = context:push_scope('block')
  local ast = node.attr.loadedast
  if node.attr.runtime_require then
    if node.attr.modulename then
      node:raisef("compile time module '%s' not found", node.attr.modulename)
    else
      node:raisef('runtime require is not supported in C backend yet')
    end
  end
  assert(ast)
  scope.staticstorage = true
  local bracepos = emitter:get_pos()
  emitter:add_indent_ln('{')
  local lastpos = emitter:get_pos()
  emitter:add(ast)
  if emitter:get_pos() == lastpos then
    emitter:remove_until_pos(bracepos)
  else
    emitter:add_indent_ln('}')
  end
  context:pop_scope()
end

return builtins
