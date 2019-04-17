module handlebars.components.if_;

import handlebars.components.base;

import std.exception;

version(unittest) {
  import fluent.asserts;
  import std.stdio;
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
