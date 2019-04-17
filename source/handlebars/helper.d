module handlebars.helper;

import std.conv;
import std.string;
import std.algorithm;
import std.traits;

import handlebars.tokens;
import handlebars.properties;

///
class RenderHelperException : Exception {
  pure nothrow @nogc @safe this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) {
    super(msg, file, line, nextInChain);
  }
}

///
string getHelper(U)(U value, Token token) if (is(U == struct) || is(U == class)) {
  return getHelper(value, value, token);
}

///
string getHelper(T, U)(T controller, U value, Token token, size_t pathStart = 0) if (is(U == struct) || is(U == class)) {
  static immutable ignoredMembers = [ __traits(allMembers, Object), "content", "lifecycle", "render"];
  auto pieces = token.value.split('.')[pathStart..$];

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
          mixin(genHelperValues!(memberName, Parameters!field));
          mixin("return value." ~ memberName ~ "(" ~ genHelperParams!(memberName, Parameters!field) ~ ").to!string;");
        } else {
          mixin("return getHelper(controller, value." ~ memberName ~ `, token, pathStart + 1);`);
        }
      }
    }
  }}

  throw new RenderHelperException("`" ~ token.value ~ "` can not be rendered becaues it is not defined.");
}

///
string getHelper(T, U)(T controller, U value, Token, size_t) if (!is(U == struct) && !is(U == class)) {
  throw new RenderHelperException("The helpers must be inside a struct or a class.");
}

///
static string genHelperValues(string prefix, List...)() {
  string result;
  size_t index;

  static foreach (T; List) {{
    string property = `token.properties.list[` ~ index.to!string ~ `]`;
    string var = prefix ~ "_" ~ index.to!string;

    result ~= T.stringof ~ " " ~ var ~ ";";
    result ~= `if(` ~ property ~ `.isEvaluated) {`;
    result ~= var ~ ` = `~ property ~`.get!(` ~ T.stringof ~ ");";
    result ~= `} else { ` ~ var ~ ` = evaluate!(` ~ T.stringof ~ `)(controller, ` ~ property ~ `.value); }`;
    index++;
  }}

  return result;
}

///
static string genHelperParams(string prefix, List...)() {
  string result;
  string glue;
  size_t index;

  static foreach (T; List) {
    result ~= glue ~ prefix ~ "_" ~ index.to!string;
    glue = ",";
    index++;
  }

  return result;
}
