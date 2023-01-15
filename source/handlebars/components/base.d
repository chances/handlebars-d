module handlebars.components.base;

public import handlebars.tokens;
public import handlebars.lifecycle;
public import handlebars.properties;

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
interface IHbsComponent {
  void content(Token[]);
  void lifecycle(HandlebarsLifecycle);

  Token[] content();
  HandlebarsLifecycle lifecycle();

  string yield();
}

///
abstract class HbsComponent(string tpl = "{{yield}}") : IHbsComponent {
  ///
  private {
    Token[] _content;
    HandlebarsLifecycle _lifecycle;
  }

  void content(Token[] value) {
    this._content = value;
  }

  void lifecycle(HandlebarsLifecycle value) {
    this._lifecycle = value;
  }

  Token[] content() {
    return this._content;
  }

  HandlebarsLifecycle lifecycle() {
    return this._lifecycle;
  }

  ///
  string yield() {
    if(this.content.length == 0) {
      return "";
    }

    return this.lifecycle.yield(this.content);
  }

  string render(Component, Components...)() {
    import handlebars.tpl;
    return handlebars.tpl.render!(tpl, Component, Components)(cast(Component) this);
  }
}
