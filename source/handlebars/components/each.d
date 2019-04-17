module handlebars.components.each;

import handlebars.components.base;

import std.exception;
import std.conv;

/// Component that will handle the if blocks
class EachComponent : HbsComponent!"" {
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
  string render(Component, Components...)() {
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
