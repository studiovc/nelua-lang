require 'busted.runner'()

local assert = require 'spec.tools.assert'

describe("Nelua runner should", function()

it("compile simple programs" , function()
  assert.run('--generator lua --no-cache --compile examples/helloworld.nelua')
  assert.run('--generator c --no-cache --compile examples/helloworld.nelua')
  assert.run('--generator lua --compile-binary examples/helloworld.nelua')
  assert.run('--generator c --compile-binary examples/helloworld.nelua')
end)

it("run simple programs", function()
  assert.run({'--generator', 'c', '--no-cache', '--timing', '--eval', "return 0"})
  assert.run('--generator lua examples/helloworld.nelua', 'hello world')
  assert.run('--generator c examples/helloworld.nelua', 'hello world')
  assert.run({'--generator', 'lua', '--eval', ""}, '')
  assert.run({'--lint', '--eval', ""})
  assert.run({'--generator', 'lua', '--eval', "print(arg[1])", "hello"}, 'hello')
  assert.run({'--generator', 'c', '--eval', ""})
  assert.run({'--generator', 'c', '--cflags="-Wall"', '--eval',
    "!!cflags '-Wextra' !!linklib 'm' !!ldflags '-s'"})
end)

it("error on parsing an invalid program" , function()
  assert.run_error('--aninvalidflag', 'unknown option')
  assert.run_error('--lint --eval invalid')
  assert.run_error('--lint invalid', 'invalid: No such file or directory')
  --assert.run_error({'--generator', 'c', '--eval', "f()"}, 'undefined')
  assert.run_error({'--generator', 'lua', '--eval', "local a = 1_x"}, 'literal suffix "_x" is not defined')
  assert.run_error('--generator c --cc invgcc examples/helloworld.nelua', 'failed to retrive compiler information')
end)

it("print correct generated AST" , function()
  assert.run('--print-ast examples/helloworld.nelua', [[Block {
  {
    Call {
      {
        String {
          "hello world",
          nil
        }
      },
      Id {
        "print"
      },
      true
    }
  }
}]])
  assert.run('--print-analyzed-ast examples/helloworld.nelua', [[Block {
  {
    Call {
      attr = {
        calleetype = "any",
        sideeffect = true,
        type = "varanys",
      },
      {
        String {
          attr = {
            compconst = true,
            type = "string",
            value = "hello world",
          },
          "hello world",
          nil
        }
      },
      Id {
        attr = {
          builtin = true,
          codename = "print",
          const = true,
          lvalue = true,
          name = "print",
          type = "any",
        },
        "print"
      },
      true
    }
  }
}]])
end)

it("print correct generated code", function()
  assert.run('--generator lua --print-code examples/helloworld.nelua', 'print("hello world")')
end)

end)