module handlebars.tpl;

import std.array;
import std.string;
import std.traits;
import std.algorithm;
import std.conv;
import std.exception;
import std.meta;

import handlebars.tokens;
import handlebars.lifecycle;
import handlebars.helper;
import handlebars.components.all;

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
    ComponentGroup!(NoDuplicates!Components) components;
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
  string render(Token[] tokens)() {
    enum token = tokens[0];

    static if(components.exists(token.value) && token.type != Token.Type.openBlock) {
      return components.get(controller, token, Token.empty, this);
    }
    else static if(token.type == Token.Type.plain) {
      return token.value;
    }
    else static if(token.type == Token.Type.value) {
      return getField!(T, token.value)(controller);
    }
    else static if(token.type == Token.Type.helper) {
      return getHelper_!(T, token)(controller);
    }
    else static if(token.type == Token.Type.openBlock) {
      enforce(components.exists(token.value), "There is no component defined as `" ~ token.value ~ "`.");

      return components.get!tokens(controller, this);
    } else {
      return "";
    }
  }

  ///
  private string getField(U)(U value, string fieldName) {
    static immutable ignoredMembers = [ __traits(allMembers, Object), "render", "content" ];
    auto pieces = fieldName.splitMemberAccess;

    static foreach (memberName; __traits(allMembers, U)) {{
      static if(__traits(hasMember, U, memberName)) {
        enum protection = __traits(getProtection, __traits(getMember, U, memberName));
      } else {
        enum protection = "";
      }

      static if(protection == "public" && memberName != "this" && !ignoredMembers.canFind(memberName)) {
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

              if(pieces.length > 2) {
                static if(isAggregateType!(ForeachType!(FieldType))) {
                  mixin(`return getField(value.` ~ memberName ~ `[index], pieces[2..$].join("."));`);
                }
              } else {
                mixin(`return value.` ~ memberName ~ `[index].to!string;`);
              }

            } else static if (is(FieldType == struct) || is(FieldType == class)) {
              mixin(`return getField(value.` ~ memberName ~ `, pieces[1..$].join("."));`);
            } else {
              mixin(`return value.` ~ memberName ~ `.to!string;`);
            }
          }
        }
      }
    }}

    return "";
  }

  ///
  private string getField(U, string fieldName)(U value) {
    mixin(`return value.` ~ fieldName ~ `.to!string;`);
  }

  ///
  private string getHelper_(U, Token token)(U value) {
    enum pieces = "controller" ~ token.value.split(".");
    enum path = pieces[0..$-1].join(".");
    enum memberName = pieces[pieces.length - 1];

    mixin(`enum protection = __traits(getProtection, __traits(getMember, typeof(`~path~`), memberName));`);

    static assert(protection == "public", "The member used in hbs template `" ~ path ~ "." ~ memberName ~ "` must be public.");

    mixin(`alias Params = Parameters!(` ~ path ~ `.` ~ memberName ~ `);`);
    mixin(`string result = ` ~ path ~ `.` ~ memberName ~ `(` ~ helperParams!(Params)(token.properties.list) ~ `).to!string;`);

    return result;
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

/// Render a template at runtime
string render(T, Components...)(string tplValue, T controller) {
  auto tokens = TokenRange(tplValue);
  auto context = new RenderContext!(T, IfComponent, EachComponent, ScopeComponent, NoDuplicates!Components)(controller);

  return tokens.tokenLevelRange.map!(a => context.render(a)).joiner.array.to!string;
}

/// Render a template at ctfe
string render(string tplValue, T, Components...)(T controller) {
  enum tokens = TokenRange(tplValue).tokenLevelRange.array;
  scope context = new RenderContext!(T, IfComponent, EachComponent, ScopeComponent, NoDuplicates!Components)(controller);

  string result;

  static foreach(group; tokens) {
    result ~= context.render!(group);
  }

  return result;
}


/// Render a template at ctfe
string render(Token[] tokens, T, Components...)(T controller) {
  scope context = new RenderContext!(T, NoDuplicates!Components)(controller);

  string result;
  enum groups = tokens.tokenLevelRange.array;

  static foreach(group; groups) {
    result ~= context.render!(group);
  }

  return result;
}

/// Rendering an empty string
unittest {
  enum tpl = "";
  struct Controller {}

  render(tpl, Controller()).should.equal("");
}

/// Rendering an empty string at ctfe
unittest {
  enum tpl = "";
  struct Controller {}

  render!(tpl)(Controller()).should.equal("");
}

/// Rendering a string value
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    string value;
  }

  render(tpl, Controller("2")).should.equal("2");
}

/// Rendering a string value at ctfe
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    string value;
  }

  render!(tpl)(Controller("2")).should.equal("2");
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

/// Rendering a string property at ctfe
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    string value() {
      return "3";
    }
  }

  render!(tpl)(Controller()).should.equal("3");
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


/// Rendering a string property at ctfe
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    string value() {
      return "3";
    }
  }

  render!(tpl)(Controller()).should.equal("3");
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


/// Rendering a numeric property at ctfe
unittest {
  enum tpl = "{{value}}";

  struct Controller {
    int value() {
      return 3;
    }
  }

  render!(tpl)(Controller()).should.equal("3");
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

/// Rendering a numeric struct subproperty at ctfe
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

  render!(tpl)(Controller()).should.equal("3");
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

  render!(tpl)(Controller()).should.equal("value");
}

/// Rendering a helper with int param
unittest {
  enum tpl = `{{helper 5}}`;

  struct Controller {
    int helper(int value) {
      return value;
    }
  }

  render!(tpl)(Controller()).should.equal("5");
}

/// Rendering a nested helper with int param
unittest {
  enum tpl = `{{child.helper 5}}`;

  struct Child {
    int helper(int value) {
      return value;
    }
  }

  struct Controller {
    Child child;
  }

  render!(tpl)(Controller()).should.equal("5");
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

  render!(tpl)(Controller()).should.equal("12");
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

  render!(tpl)(Controller()).should.equal("8");
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

  render!(tpl)(Controller()).should.equal("5 true test");
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
  class Component : HbsComponent!"" {
    int a;
    int b;

    string render(Component, Components...)() {
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

  render(tpl, Controller()).should.equal("text");
}

/// Rendering if block at ctfe
unittest {
  enum tpl = `{{#if value}}text{{/if}}`;

  struct Controller {
    int value() {
      return 2;
    }
  }

  render!(tpl)(Controller()).should.equal("text");
}

/// Don't render if blocks if the condition is not satisfied
unittest {
  enum tpl = `{{#if false}}text{{/if}}`;

  struct Controller {
    int value() {
      return 2;
    }
  }

  render!(Controller)(tpl, Controller()).should.equal("");
}

/// Rendering if block and stop at the else block if the value is evaluated to true
unittest {
  struct Controller {
    bool value = true;
  }

  enum tpl = `{{#if true}}text{{else value}}other{{/if}}`;
  render(tpl, Controller()).should.equal("text");
}

/// Rendering at ctfe an if block and stop at the else block if the value is evaluated to true
unittest {
  struct Controller {
    bool value = true;
  }

  enum tpl = `{{#if true}}text{{else value}}other{{/if}}`;
  render!(tpl)(Controller()).should.equal("text");
}

/// Rendering at ctfe the right else
unittest {
  struct Controller {
    bool value = true;
  }

  enum tpl = `{{#if false}}text{{else false}}other{{else value}}this one{{else}}default{{/if}}`;
  render!(tpl)(Controller()).should.equal("this one");
}

/// Rendering at ctfe an if block should render the final else
unittest {
  struct Controller {
    bool value = true;
  }

  enum tpl = `{{#if false}}text{{else false}}other{{else}}{{value}}{{/if}}`;
  render!(tpl)(Controller()).should.equal("true");
}

/// Rendering at ctfe nested if blocks
unittest {
  struct Controller {
    bool value = true;
  }

  enum tpl = `{{#if false}}text{{else}} <-- {{#if value}}true{{else}}false{{/if}} --> {{/if}}`;
  render!(tpl)(Controller()).should.equal(" <-- true --> ");
}

/// Rendering an each block
unittest {
  struct Controller {
    int[] list() {
      return [1,2,3,4];
    }
  }

  enum tpl = `{{#each list as |item|}} {{item}} {{/each}}`;
  render(tpl, Controller()).should.equal(" 1  2  3  4 ");
}

/// Rendering an each block with a list of structs
unittest {
  struct Child {
    string name;
  }

  struct Controller {
    Child[] list;
  }

  enum tpl = `{{#each list as |item|}} {{item.name}} {{/each}}`;
  render(tpl, Controller([Child("name1"), Child("name2")])).should.equal(" name1  name2 ");
}

/// Rendering an indexed each block
unittest {
  struct Controller {
    int[] list() {
      return [1,2,3,4];
    }
  }

  enum tpl = `{{#each list as |item index|}} {{index}}{{item}} {{/each}}`;
  render!(Controller)(tpl, Controller()).should.equal(" 01  12  23  34 ");
}

/// Rendering an indexed each block with ctfe parsing
unittest {
  struct Controller {
    int[] list() {
      return [1,2,3,4];
    }
  }

  enum tpl = `{{#each list as |item index|}} {{index}}{{item}} {{/each}}`;
  render!(tpl)(Controller()).should.equal(" 01  12  23  34 ");
}


/// Rendering an indexed each block with ctfe parsing
unittest {
  struct Controller {
    int[string] list() {
      return ["a": 1, "b": 2, "c": 3,"d": 4];
    }
  }

  enum tpl = `{{#each list as |item index|}} {{index}}{{item}} {{/each}}`;
  render!(tpl)(Controller()).should.equal(" c3  a1  b2  d4 ");
}

/// Rendering an nested indexed each block with ctfe parsing
unittest {
  struct Child {
    int[] numbers() {
      return [1,2,3,4];
    }
  }

  struct Controller {
    Child[] list() {
      return [Child(), Child()];
    }
  }

  enum tpl = `{{#each list as |child index|}} {{index}}.[{{#each child.numbers as |number index|}}{{index}}.{{number}} {{/each}}] {{/each}}`;
  render!(tpl)(Controller()).should.equal(" 0.[0.1 1.2 2.3 3.4 ]  1.[0.1 1.2 2.3 3.4 ] ");
}

/// Rendering parent values in an nested indexed each block with ctfe parsing
unittest {
  struct Child {
    int[] numbers() {
      return [1,2,3,4];
    }
  }

  struct Controller {
    string parentValue1 = "test1";
    string parentValue2 = "test2";

    Child[] list() {
      return [Child(), Child()];
    }
  }

  enum tpl = `{{#each list as |child parent_index|}} {{parentValue1}} [{{#each child.numbers as |number index|}}{{parentValue2}} {{parent_index}}.{{index}}.{{number}} {{/each}}] {{/each}}`;
  render!(tpl)(Controller()).should.equal(" test1 [test2 0.0.1 test2 0.1.2 test2 0.2.3 test2 0.3.4 ]  test1 [test2 1.0.1 test2 1.1.2 test2 1.2.3 test2 1.3.4 ] ");
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
  render(tpl, Controller()).should.equal(" 1:2 ");
}

version(unittest) {
  enum tplComponent = import("test-component.hbs");
  class TestComponent : HbsComponent!(tplComponent) {
    ///
    enum ComponentName = "test-component";

    int a;
    int b;
  }
}

/// Rendering component with external template at runtime
unittest {
  struct Controller {
    int a = 1;
    int b = 2;
  }

  enum tpl = `{{test-component a=a b=b}}`;
  render!(Controller, TestComponent)(tpl, Controller()).should.equal("1:2\n");
}

/// Rendering component with external template at ctfe
unittest {
  struct Controller {
    int a = 1;
    int b = 2;
  }

  enum tpl = `{{test-component a=a b=b}}`;
  render!(tpl, Controller, TestComponent)(Controller()).should.equal("1:2\n");
}


version(unittest) {
  enum tplEachComponent = import("test-each-component.hbs");
  class TestEachComponent : HbsComponent!(tplEachComponent) {
    ///
    enum ComponentName = "test-each-component";

    int[] list = [1,2,3,4,5];
  }

  enum tplSeparatorComponent = import("separator-component.hbs");
  class SeparatorComponent : HbsComponent!(tplSeparatorComponent) {
    ///
    enum ComponentName = "separator-component";

    int value;
  }
}

/// Rendering component with external template at ctfe
unittest {
  struct Controller {
    int[] list = [10,20,30,40,50];
  }

  enum tpl = `{{test-each-component list=list}}`;
  render!(tpl, Controller, TestEachComponent, SeparatorComponent)(Controller()).should.equal("10,\n20,\n30,\n40,\n50,\n\n");
}

/// Rendering component with external template at runtime
unittest {
  struct Controller {
    int[] list = [10,20,30,40,50];
  }

  enum tpl = `{{test-each-component list=list}}`;
  render!(Controller, TestEachComponent, SeparatorComponent)(tpl, Controller()).should.equal("10,\n20,\n30,\n40,\n50,\n\n");
}
