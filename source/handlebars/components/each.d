module handlebars.components.each;

import handlebars.components.base;
import handlebars.tpl;

import std.exception;
import std.conv;
import std.traits;
import std.algorithm;

/// Component that will handle the if blocks
class EachComponentCt(Token[] tokens, Properties properties) : HbsComponent!"" {
  enum ComponentName = "each";

  ///
  string render(T, Components...)(T controller) {
    string result;

    static if(properties.localName != "") {
      mixin(`alias NameType = typeof(controller.` ~ properties.name ~ `);`);
      static if(isCallable!(NameType)) {
        alias __Type = ForeachType!(ReturnType!NameType);
      } else {
        alias __Type = ForeachType!(NameType);
      }
    }

    class TmpController {
      private T controller;

      static if(properties.localName != "") {
        mixin(`__Type ` ~ properties.localName ~ `;`);
      }

      static if(properties.indexName != "") {
        mixin(`string ` ~ properties.indexName ~ `;`);
      }

      mixin(genControllerFields!T());
    }

    auto tmpController = new TmpController;
    tmpController.controller = controller;

    mixin(genForeach());

    return result;
  }

  private static string genForeach() {
    string result;

    result ~= `foreach(i, value; controller.` ~ properties.name ~ `) {`;

    static if(properties.localName != "") {
      result ~= `tmpController.` ~ properties.localName ~ ` = value;`;
    }

    static if(properties.indexName != "") {
      result ~= `tmpController.` ~ properties.indexName ~ ` = i.to!string;`;
    }

    result ~= `result ~= handlebars.tpl.render!(tokens, TmpController, Components)(tmpController);`;

    result ~= `}`;

    return result;
  }

  private static string genControllerFields(T)() {
    static immutable ignoredMembers = [ __traits(allMembers, Object), "this", "ComponentName", "lifecycle",
      "render", properties.localName, properties.indexName ];

    string result;

    static foreach (memberName; __traits(allMembers, T)) {{
      static if(!ignoredMembers.canFind(memberName)) {
        enum protection = __traits(getProtection, __traits(getMember, T, memberName));

        static if (protection == "public") {
          mixin(`alias field = T.` ~ memberName ~ `;`);

          static if(isCallable!(field) && arity!field > 0) {
            result ~= `auto ` ~ memberName ~ `(` ~ genParams!(Parameters!field) ~ `) {
                        return controller.` ~ memberName ~ `(` ~  genVals!(Parameters!field) ~ `);
                      }`;
          } else {
            result ~= `auto ` ~ memberName ~ `() { return controller.` ~ memberName ~ `; }`;
          }
        }
      }
    }}

    return result;
  }

  private static string genParams(T...)() {
    string result;

    return result;
  }

  private static string genVals(T...)() {
    string result;

    return result;
  }
}

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
