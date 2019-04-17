module handlebars.components.all;

public import handlebars.components.base;
public import handlebars.components.each;
public import handlebars.components.scope_;
public import handlebars.components.if_;


import handlebars.helper;

import std.algorithm;
import std.traits;
import std.exception;
import std.conv;

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
          return (cast(Component)instance).render!(Component, Components)();
        }

        static if(__traits(hasMember, Component, "ComponentName")) {
          if(Component.ComponentName == token.value) {
            setupFields(controller, cast(Component) instance, token.properties);
            return (cast(Component)instance).render!(Component, Components)();
          }
        }
      }

      throw new RenderComponentException("Can't render component `" ~ token.value ~ "`");
    }

    ///
    IHbsComponent getInstance(T)(T controller, Token token) {
      static foreach(Component; Components) {{
        static if (__traits(hasMember, Component, "ComponentName")) {
          immutable name = Component.ComponentName;
        } else {
          immutable name = Component.stringof;
        }

        if(token.value == name) {
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

      static foreach (memberName; __traits(allMembers, U)) {{
        enum protection = __traits(getProtection, __traits(getMember, U, memberName));

        static if(protection == "public" && memberName != "this" && memberName != "content" && !ignoredMembers.canFind(memberName)) {
          mixin(`alias field = U.` ~ memberName ~ `;`);

          static if(!isCallable!field && !is(typeof(field) == void)) {
            enum property = `properties.hash["` ~ memberName ~ `"]`;

            if(memberName in properties.hash) {
              mixin(`if(!`~property~`.isEvaluated) {
                instance.` ~ memberName ~ ` = evaluate!(` ~ typeof(field).stringof ~ `)(controller, ` ~ property ~ `.value);
              }`);

              static if(isSomeString!(typeof(field)) || isBuiltinType!(typeof(field))) {
                mixin(`if(`~property~`.isEvaluated) {
                  instance.` ~ memberName ~ ` = `~property~`.value.to!(` ~ typeof(field).stringof ~ `);
                }`);
              } else {
                mixin(`if(`~property~`.isEvaluated) {
                  throw new RenderComponentException("Can't pass evaluated property to ` ~ memberName ~ `");
                }`);
              }
            }
          }
        }
      }}
    }
}
