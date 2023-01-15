module handlebars.lifecycle;

import handlebars.tokens;

alias OnYield = string delegate(Token[]);
alias OnEvaluateBoolean = bool delegate(string);
alias OnEvaluateLong = long delegate(string);

///
interface HandlebarsLifecycle {
  ///
  string yield(Token[] tokens);

  ///
  bool evaluateBoolean(string value);

  ///
  long evaluateLong(string value);
}

class MockLifecycle: HandlebarsLifecycle {
  OnYield onYield;
  OnEvaluateBoolean onEvaluateBoolean;
  OnEvaluateLong onEvaluateLong;

  ///
  string yield(Token[] tokens) {
    return onYield(tokens);
  }

  ///
  bool evaluateBoolean(string value) {
    return onEvaluateBoolean(value);
  }

  ///
  long evaluateLong(string value) {
    return onEvaluateLong(value);
  }
}
