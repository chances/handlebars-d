module handlebars.components.if_;

import handlebars.components.base;
import handlebars.tpl;

import std.exception;
import std.conv;

version(unittest) {
  import fluent.asserts;
  import std.stdio;
}

/// Component that will handle the if blocks at ctfe
class IfComponentCt(Token[] tokens, Properties properties) : HbsComponent!"" {
  enum ComponentName = "if";

  private {
    bool value;
  }

  this(bool value) {
    this.value = value;
  }

  ///
  string render(T, Components...)(T controller) {
    string result;

    mixin(genIf());

    return result;
  }

  private static string genIf() {
    string code = `if(` ~ properties.list[0].toParam() ~ `) {`;

    size_t start_index;
    size_t end_index;
    size_t nested;

    foreach(token; tokens) {
      if(token.value == "if" && token.type != Token.Type.openBlock) {
        nested++;
      }

      if(token.value == "if" && token.type != Token.Type.closeBlock) {
        nested--;
      }

      if(nested > 0) {
        end_index++;
        continue;
      }

      if(token.value == "else" && token.type != Token.Type.plain) {
        code ~= `result = handlebars.tpl.render!(tokens[`~start_index.to!string~`..`~end_index.to!string~`], T, Components)(controller); }`;

        if(token.properties.list.length == 0) {
          code ~= ` else { `;
        } else {
          code ~= ` else if(` ~ token.properties.list[0].toParam() ~ `) { `;
        }

        start_index = end_index+1;
      }

      end_index++;
    }

    code ~= `result = handlebars.tpl.render!(tokens[`~start_index.to!string~`..`~end_index.to!string~`], T, Components)(controller);`;

    return code ~ ` }`;
  }
}

/// Component that will handle the if blocks
class IfComponent : HbsComponent!"" {

  private bool value;

  enum ComponentName = "if";

  ///
  this(bool value) {
    this.value = value;
  }

  ///
  string render(Component, Components...)() {
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

  condition.render!(IfComponent).should.equal("true");
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
  condition.render!(IfComponent).should.equal("");
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

  condition.render!(IfComponent).should.equal("true");
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

  condition.render!(IfComponent).should.equal("false");
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

  condition.render!(IfComponent).should.equal("2");
}
