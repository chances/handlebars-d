module tpl.component;

import std.exception;
import std.algorithm;
import std.traits;
import std.conv;
import std.array;

import tpl.properties;
import tpl.tokens;
import tpl.helper;
import tpl.lifecycle;

version(unittest) {
  import fluent.asserts;
  import std.stdio;
}

///
class RenderComponentException : Exception {
  pure nothrow @nogc @safe this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) {
    super(msg, file, line, nextInChain);
  }
}

alias OnYield = string delegate(Token[]);
alias OnEvaluateBoolean = bool delegate(string);
alias OnEvaluateLong = long delegate(string);

///
abstract class HbsComponent {
  ///
  Token[] content;

  Lifecycle lifecycle;

  ///
  string yield() {
    if(this.content.length == 0) {
      return "";
    }

    return this.lifecycle.yield(this.content);
  }

  ///
  string render();
}

///
struct ComponentGroup(Components...) {

  static:
    ///
    bool exists(string componentName) {
      static foreach(Component; Components) {{

        static if (__traits(hasMember, Component, "ComponentName")) {
          immutable name = Component.ComponentName;
        } else {
          immutable name = Component.stringof;
        }

        if(componentName == name) {
          return true;
        }
      }}

      return false;
    }

    ///
    string get(T)(T controller, Token token, Token[] content, Lifecycle lifecycle) {
      auto instance = getInstance(controller, token);
      instance.lifecycle = lifecycle;
      instance.content = content;

      enforce!RenderComponentException(instance !is null,
        "Can't initilize component `" ~ token.value ~ "`.");

      static foreach(Component; Components) {
        if(Component.stringof == token.value) {
          setupFields(controller, cast(Component) instance, token.properties);
        }
      }

      return instance.render();
    }

    ///
    HbsComponent getInstance(T)(T controller, Token token) {
      static foreach(Component; Components) {{
        static if (__traits(hasMember, Component, "ComponentName")) {
          immutable name = Component.ComponentName;
        } else {
          immutable name = Component.stringof;
        }

        if(token  .value == name) {
          static if(__traits(hasMember, Component, "__ctor")) {
            static foreach (t; __traits(getOverloads, Component, "__ctor")) {

              static if(arity!t != 1 || (arity!t == 1 && !is(Parameters!t[0] == Properties))) {
                if(arity!t == token.properties.list.length) {
                  mixin(genHelperValues!("ctor", Parameters!t));
                  mixin("return new " ~ Component.stringof ~ "(" ~ genHelperParams!("ctor", Parameters!t) ~ ");");
                }
              }
            }
          } else {
            return new Component();
          }
        }
      }}

      static foreach(Component; Components) {{
        static if (__traits(hasMember, Component, "ComponentName")) {
          immutable name = Component.ComponentName;
        } else {
          immutable name = Component.stringof;
        }

        if(token.value == name) {
          static if(__traits(hasMember, Component, "__ctor")) {
            static foreach (t; __traits(getOverloads, Component, "__ctor")) {
              static if(arity!t == 1 && is(Parameters!t[0] == Properties)) {
                mixin("return new " ~ Component.stringof ~ "(token.properties);");
              }
            }
          }
        }
      }}

      throw new RenderComponentException("The `"~token.value~"` component can't be rendered with the provided fields.");
    }

    ///
    private void setupFields(T, U)(T controller, U instance, Properties properties) {
      static immutable ignoredMembers = [ __traits(allMembers, Object), "ComponentName", "lifecycle" ];

      static foreach (memberName; __traits(allMembers, U)) {
        static if(memberName != "this" && memberName != "content" && !ignoredMembers.canFind(memberName)) {{
          mixin(`alias field = U.` ~ memberName ~ `;`);

          static if(!isCallable!field && __traits(getProtection, field) == "public") {
            enum property = `properties.hash["` ~ memberName ~ `"]`;

            if(memberName in properties.hash) {
              mixin(`if(`~property~`.isEvaluated) {
                instance.` ~ memberName ~ ` = `~property~`.value.to!` ~ typeof(field).stringof ~ `;
              } else {
                instance.` ~ memberName ~ ` = evaluate!(` ~ typeof(field).stringof ~ `)(controller, ` ~ property ~ `.value);
              }`);
            }
          }
        }}
      }
    }
}

/// Component that will handle the if blocks
class IfComponent : HbsComponent {

  private bool value;

  enum ComponentName = "if";

  ///
  this(bool value) {
    this.value = value;
  }

  ///
  override string render() {
    bool shouldOutput = this.value;
    Token[] result;

    foreach(item; this.content) {
      if(item.value == "else" && item.type != Token.Type.plain && shouldOutput) {
        break;
      }

      if(shouldOutput) {
        result ~= item;
      }

      if(item.value == "else" && item.type == Token.Type.value) {
        shouldOutput = true;
      }

      if(item.value == "else" && item.type == Token.Type.helper) {
        enforce(item.properties.list.length > 1, "Invalid else if format.");
        enforce(item.properties.list[0].value == "if", "Expected `if` after `else`.");

        shouldOutput = this.lifecycle.evaluateBoolean(item.properties.list[1].value);
      }
    }

    if(result.length == 0) {
      return "";
    }

    return this.lifecycle.yield(result);
  }
}

/// Render an if block if the condition is satisfied
unittest {
  string mockYeld(Token[] tokens) {
    tokens.length.should.equal(1);
    return tokens[0].value;
  }

  auto mockLifecycle = new MockLifecycle();
  mockLifecycle.onYield = &mockYeld;

  auto condition = new IfComponent(true);
  condition.lifecycle = mockLifecycle;

  condition.content = [ Token(Token.Type.plain, "true") ];

  condition.render.should.equal("true");
}

/// Don't render an if block if the condition is not satisfied
unittest {
  bool called;

  string mockYeld(Token[] tokens) {
    called = true;
    return tokens[0].value;
  }

  auto mockLifecycle = new MockLifecycle();
  mockLifecycle.onYield = &mockYeld;

  auto condition = new IfComponent(false);
  condition.lifecycle = mockLifecycle;

  condition.content = [ Token(Token.Type.plain, "true") ];

  called.should.equal(false);
  condition.render.should.equal("");
}

/// Render an if until the else token
unittest {
  string mockYeld(Token[] tokens) {
    tokens.length.should.equal(1);
    return tokens[0].value;
  }

  auto mockLifecycle = new MockLifecycle();
  mockLifecycle.onYield = &mockYeld;

  auto condition = new IfComponent(true);
  condition.lifecycle = mockLifecycle;

  condition.content = [
    Token(Token.Type.plain, "true"),
    Token(Token.Type.value, "else"),
    Token(Token.Type.plain, "false") ];

  condition.render.should.equal("true");
}

/// Render the else when the if is not satisfied
unittest {
  string mockYeld(Token[] tokens) {
    tokens.length.should.equal(1);
    return tokens[0].value;
  }

  auto mockLifecycle = new MockLifecycle();
  mockLifecycle.onYield = &mockYeld;

  auto condition = new IfComponent(false);
  condition.lifecycle = mockLifecycle;

  condition.content = [
    Token(Token.Type.plain, "true"),
    Token(Token.Type.value, "else"),
    Token(Token.Type.plain, "false") ];

  condition.render.should.equal("false");
}

/// Render the else when the if is not satisfied
unittest {
  string mockYeld(Token[] tokens) {
    tokens.length.should.equal(1);
    return tokens[0].value;
  }

  bool mockBoolEval(string value) {
    return value == "true";
  }

  auto mockLifecycle = new MockLifecycle();
  mockLifecycle.onYield = &mockYeld;
  mockLifecycle.onEvaluateBoolean = &mockBoolEval;

  auto condition = new IfComponent(false);
  condition.lifecycle = mockLifecycle;

  condition.content = [
    Token(Token.Type.plain, "true"),
    Token(Token.Type.helper, "else", Properties("if false")),
    Token(Token.Type.plain, "3"),
    Token(Token.Type.helper, "else", Properties("if true")),
    Token(Token.Type.plain, "2") ];

  condition.render.should.equal("2");
}

/// Component that will handle the if blocks
class EachComponent : HbsComponent {
  enum ComponentName = "each";

  private {
    string name;
    string localName;
    string indexName;
  }

  ///
  this(Properties properties) {
    enforce!RenderComponentException(properties.list.length == 0, "list as |item| or list as |item index| expected");
    enforce!RenderComponentException(properties.name != "", "list as |item| or list as |item index| expected");
    enforce!RenderComponentException(properties.localName != "", "list as |item| or list as |item index| expected");

    this.name = properties.name;
    this.localName = properties.localName;
    this.indexName = properties.indexName;
  }

  ///
  override string render() {
    string result;

    long len = this.lifecycle.evaluateLong(this.name ~ ".length");

    foreach(i; 0..len) {
      Token[] list;
      string props = `"` ~ name ~ `" "` ~ localName ~ `" "` ~ i.to!string ~ `" `;

      if(indexName != "") {
        props ~= `"` ~ indexName ~ `"`;
      } else {
        props ~= `""`;
      }

      list ~= Token(Token.Type.openBlock, "scope", Properties(props));
      list ~= this.content;
      list ~= Token(Token.Type.closeBlock, "scope");

      result ~= lifecycle.yield(list);
    }

    return result;
  }
}

/// Component that will handle the if blocks
class ScopeComponent : HbsComponent {

  enum ComponentName = "scope";

  private {
    string propertyName;
    string localName;
    string index;
    string indexName;
  }

  ///
  this(string propertyName, string localName, string index, string indexName) {
    this.propertyName = propertyName;
    this.localName = localName;
    this.index = index;
    this.indexName = indexName;
  }

  ///
  override string render() {
    Token[] localContent;

    foreach(token; this.content) {
      if(token.value == localName) {
        token.value = propertyName ~ "[" ~ index ~ "]";
      }

      if(token.value == indexName) {
        token.value = index;
        token.type = Token.Type.plain;
      }

      foreach(ref property; token.properties.list) {
        if(property.isEvaluated) {
          continue;
        }

        if(property.value == localName) {
          property.value = propertyName ~ "[" ~ index ~ "]";
        }

        if(property.value == indexName) {
          property.value = index;
          property.isEvaluated = true;
        }
      }

      foreach(ref property; token.properties.hash) {
        if(property.isEvaluated) {
          continue;
        }

        if(property.value == localName) {
          property.value = propertyName ~ "[" ~ index ~ "]";
        }

        if(property.value == indexName) {
          property.value = index;
          property.isEvaluated = true;
        }
      }

      localContent ~= token;
    }

    return lifecycle.yield(localContent);
  }
}
