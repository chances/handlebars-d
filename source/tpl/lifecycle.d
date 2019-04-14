module tpl.lifecycle;

import tpl.tokens;

alias OnYield = string delegate(Token[]);
alias OnEvaluateBoolean = bool delegate(string);
alias OnEvaluateLong = long delegate(string);

///
interface Lifecycle {
  ///
  string yield(Token[] tokens);

  ///
  bool evaluateBoolean(string value);

  ///
  long evaluateLong(string value);
}

class MockLifecycle: Lifecycle {
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
