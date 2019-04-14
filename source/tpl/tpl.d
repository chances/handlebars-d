module tpl.tpl;

import std.array;
import std.string;
import std.traits;
import std.algorithm;
import std.conv;
import std.exception;

import tpl.tokens;
import tpl.lifecycle;
import tpl.helper;
import tpl.component;

version(unittest) {
  import fluent.asserts;
}

///
class RenderException : Exception {
  pure nothrow @nogc @safe this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) {
    super(msg, file, line, nextInChain);
  }
}

///
class RenderContext(T, Components...) : Lifecycle {
  private {
    T controller;
    ComponentGroup!(Components) components;
  }

  ///
  this(T controller) {
    this.controller = controller;
  }

  ///
  string render(Token[] tokens) {
    auto token = tokens[0];

    if(components.exists(token.value) && token.type != Token.Type.openBlock) {
      return components.get(controller, token, Token.empty, this);
    }

    if(token.type == Token.Type.plain) {
      return token.value;
    }

    if(token.type == Token.Type.value) {
      return getField!T(controller, token.value);
    }

    if(token.type == Token.Type.helper) {
      return getHelper!T(controller, token);
    }

    if(token.type == Token.Type.openBlock) {
      enforce(components.exists(token.value), "There is no component defined as `" ~ token.value ~ "`.");

      return components.get(controller,
        token,
        tokens[1..$-1],
        this);
    }

    return "";
  }

  ///
  private string getField(U)(U value, string fieldName) {

    static immutable ignoredMembers = [ __traits(allMembers, Object) ];
    auto pieces = fieldName.splitMemberAccess;

    static foreach (memberName; __traits(allMembers, U)) {
      static if(memberName != "this" && !ignoredMembers.canFind(memberName)) {
        if(pieces[0] == memberName) {
          mixin(`alias field = U.` ~ memberName ~ `;`);

          static if(isCallable!(field) && arity!field > 0) {
            throw new RenderException("`" ~ T.stringof ~ "." ~
                fieldName ~ "` can not be rendered as a value. Did you forget the template parameters?");
          } else {
            static if (isCallable!(field)) {
              alias FieldType = ReturnType!field;
            } else {
              alias FieldType = typeof(field);
            }

            static if (!isSomeString!FieldType && isArray!FieldType) {
              auto index = pieces[1][1..$-1].to!size_t;
              mixin(`return value.` ~ memberName ~ `[index].to!string;`);
            } else static if (is(FieldType == struct) || is(FieldType == class)) {
              mixin(`return getField(value.` ~ memberName ~ `, pieces[1..$].join("."));`);
            } else {
              mixin(`return value.` ~ memberName ~ `.to!string;`);
            }
          }
        }
      }
    }

    return "";
  }

  ///
  string yield(Token[] tokens) {
    return tokens.tokenLevelRange.map!(a => render(a)).joiner.array.to!string;
  }

  ///
  bool evaluateBoolean(string value) {
    return evaluate!(bool)(controller, value);
  }

  ///
  long evaluateLong(string value) {
    return evaluate!(long)(controller, value);
  }
}

///
string render(T, Components...)(string tplValue, T controller) {
  auto tokens = TokenRange(tplValue);
  auto context = new RenderContext!(T, IfComponent, EachComponent, ScopeComponent, Components)(controller);

  return tokens.tokenLevelRange.map!(a => context.render(a)).joiner.array.to!string;
}

/// Rendering an empty string
unittest {
  enum tpl = "";
  struct Controller {}

  render(tpl, Controller()).should.equal("");
}

/// Rendering a string value
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    string value;
  }

  render(tpl, Controller("2")).should.equal("2");
}

/// Rendering a string property
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    string value() {
      return "3";
    }
  }

  render(tpl, Controller()).should.equal("3");
}

/// Rendering a string property
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    string value() {
      return "3";
    }
  }

  render(tpl, Controller()).should.equal("3");
}

/// Rendering a numeric property
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    int value() {
      return 3;
    }
  }

  render(tpl, Controller()).should.equal("3");
}

/// Rendering a numeric struct subproperty
unittest {
  enum tpl = "{{child.value}}";

  struct Child {
    int value = 3;
  }

  struct Controller {
    Child child() {
      return Child();
    }
  }

  render(tpl, Controller()).should.equal("3");
}

/// Rendering a numeric class subproperty
unittest {
  enum tpl = "{{child.value}}";

  class Child {
    int value = 3;
  }

  struct Controller {
    Child child() {
      return new Child();
    }
  }

  render(tpl, Controller()).should.equal("3");
}

/// Rendering a numeric class subproperty
unittest {
  enum tpl = "{{child.value}}";

  class Child {
    int value = 3;
  }

  struct Controller {
    Child child() {
      return new Child();
    }
  }

  render(tpl, Controller()).should.equal("3");
}

/// Rendering a numeric class member
unittest {
  enum tpl = "{{child.value}}";

  class Child {
    int value = 3;
  }

  struct Controller {
    Child child;
  }

  render(tpl, Controller( new Child() )).should.equal("3");
}

/// Rendering a numeric struct member
unittest {
  enum tpl = "{{child.value}}";

  struct Child {
    int value = 3;
  }

  struct Controller {
    Child child;
  }

  render(tpl, Controller()).should.equal("3");
}

/// Rendering a string property from a class controller
unittest {
  enum tpl = "{{value}}";

  class Controller {
    string value() {
      return "3";
    }
  }

  render(tpl, new Controller()).should.equal("3");
}

/// it should not render a string method with parameters as value
unittest {
  enum tpl = "{{value}}";

  class Controller {
    string value(string param) {
      return param;
    }
  }

  render(tpl, new Controller())
    .should
    .throwException!RenderException
      .withMessage
        .equal("`Controller.value` can not be rendered as a value. Did you forget the template parameters?");
}

/// Rendering a string property from a class controller with plain values
unittest {
  enum tpl = "a {{value}} b {{value}} c";

  class Controller {
    string value() {
      return "3";
    }
  }

  auto result = render(tpl, new Controller());
  result.should.equal("a 3 b 3 c");
}

/// Rendering a helper with string param
unittest {
  enum tpl = `{{helper "value"}}`;

  struct Controller {
    string helper(string value) {
      return value;
    }
  }

  render(tpl, Controller()).should.equal("value");
}

/// Rendering a helper with int param
unittest {
  enum tpl = `{{helper 5}}`;

  struct Controller {
    int helper(int value) {
      return value;
    }
  }

  render(tpl, Controller()).should.equal("5");
}

/// Rendering a helper with property value
unittest {
  enum tpl = `{{helper value}}`;

  struct Controller {
    int helper(int value) {
      return value;
    }

    int value = 12;
  }

  render(tpl, Controller()).should.equal("12");
}

/// Rendering a helper with computed value
unittest {
  enum tpl = `{{helper value}}`;

  struct Controller {
    int helper(int value) {
      return value;
    }

    int value() {
      return 8;
    }
  }

  render(tpl, Controller()).should.equal("8");
}

/// Rendering a nested helper with bool param
unittest {
  enum tpl = `{{child.helper 5 true "test"}}`;

  struct Child {
    string helper(int number, bool value, string str) {
      return number.to!string ~ " " ~ value.to!string ~ " " ~ str;
    }
  }

  struct Controller {
    Child child;
    string value;
  }

  render(tpl, Controller()).should.equal("5 true test");
}


/// Rendering undefined helpers should throw an exception
unittest {
  enum tpl1 = `{{helper 5 true "test"}}`;
  enum tpl2 = `{{child.other 5 true "test"}}`;
  enum tpl3 = `{{value 5 true "test"}}`;
  enum tpl4 = `{{child.value 5 true "test"}}`;

  struct Child {
    string helper(int number, bool value, string str) {
      return number.to!string ~ " " ~ value.to!string ~ " " ~ str;
    }

    string value;
  }

  struct Controller {
    Child child;
  }

  render(tpl1, Controller())
    .should
    .throwException!RenderHelperException
      .withMessage
        .equal("`helper` can not be rendered becaues it is not defined.");

  render(tpl2, Controller())
    .should
    .throwException!RenderHelperException
      .withMessage
        .equal("`child.other` can not be rendered becaues it is not defined.");

  render(tpl3, Controller())
    .should
    .throwException!RenderHelperException
      .withMessage
        .equal("`value` can not be rendered becaues it is not defined.");

  render(tpl4, Controller())
    .should
    .throwException!RenderHelperException
      .withMessage
        .equal("The helpers must be inside a struct or a class.");
}

version(unittest) {
  class Component : HbsComponent {
    int a;
    int b;

    override string render() {
      auto sum = a + b;
      return this.yield ~ sum.to!string;
    }
  }
}

/// Rendering components with no blocks
unittest {
  enum tpl = `{{Component a=value b=3}}`;

  struct Controller {
    int value() {
      return 2;
    }
  }

  render!(Controller, Component)(tpl, Controller()).should.equal("5");
}

/// Rendering components with blocks
unittest {
  enum tpl = `{{#Component a=value b=3}}text 3+{{value}}={{/Component}};`;

  struct Controller {
    int value() {
      return 2;
    }
  }

  render!(Controller, Component)(tpl, Controller()).should.equal("text 3+2=5;");
}

/// Rendering if block
unittest {
  enum tpl = `{{#if value}}text{{/if}}`;

  struct Controller {
    int value() {
      return 2;
    }
  }

  render!(Controller, Component)(tpl, Controller()).should.equal("text");
}

/// Don't render if blocks if the condition is not satisfied
unittest {
  enum tpl = `{{#if false}}text{{/if}}`;

  struct Controller {
    int value() {
      return 2;
    }
  }

  render!(Controller, Component)(tpl, Controller()).should.equal("");
}

/// Rendering if block and stop at the else block if the value is evaluated to true
unittest {
  struct Controller {
    bool value = true;
  }

  enum tpl = `{{#if true}}text{{else value}}other{{/if}}`;
  render!(Controller, Component)(tpl, Controller()).should.equal("text");
}

/// Rendering an each block
unittest {
  struct Controller {
    int[] list() {
      return [1,2,3,4];
    }
  }

  enum tpl = `{{#each list as |item|}} {{item}} {{/each}}`;
  render!(Controller, Component)(tpl, Controller()).should.equal(" 1  2  3  4 ");
}

/// Rendering an indexed each block
unittest {
  struct Controller {
    int[] list() {
      return [1,2,3,4];
    }
  }

  enum tpl = `{{#each list as |item index|}} {{index}}{{item}} {{/each}}`;
  render!(Controller, Component)(tpl, Controller()).should.equal(" 01  12  23  34 ");
}

/// Rendering scope component with helper
unittest {
  struct Controller {
    int[] list = [1,2,3,4];

    string helper(int a, int b){
      return a.to!string ~ ":" ~ b.to!string;
    }
  }

  enum tpl = `{{#scope "list" "item" "1" "index" }} {{helper index item}} {{/scope}}`;
  render!(Controller, Component)(tpl, Controller()).should.equal(" 1:2 ");
}
