module handlebars.tokens;

import std.array;
import std.string;
import std.traits;
import std.conv;
import std.algorithm;

import handlebars.properties;

version(unittest) {
  import fluent.asserts;
}

///
struct Token {
  static Token[] empty;
  ///
  enum Type {
    /// tokens that should not be processed
    plain,
    value,
    helper,
    openBlock,
    closeBlock,
  }

  ///
  Type type;

  ///
  string value;

  ///
  Properties properties;
}

/// split the input into tokens
class TokenRange {
  private {
    string tpl;
    size_t index;
    size_t nextIndex;

    Token token;
  }

  static opCall(string tpl) {
    return new TokenRange(tpl);
  }

  ///
  this(string tpl) {
    this.tpl = tpl;
    next;
  }

  ///
  private void next() {
    long pos;
    token.properties = Properties("");

    if(index+2 < tpl.length && tpl[index..index+2] == "{{") {
      token.type = Token.Type.value;
      pos = tpl[index..$].indexOf("}}");

      token.value = tpl[index+2..index+pos];
      nextIndex = index+pos+2;

      auto paramPos = token.value.indexOf(' ');

      if(paramPos >= 0) {
        token.type = Token.Type.helper;
        token.properties = Properties(token.value[paramPos+1..$]);
        token.value = token.value[0..paramPos];
      }

      if(token.value[0] == '#') {
        token.type = Token.Type.openBlock;
        token.value = token.value[1..$];
      }

      if(token.value[0] == '/') {
        token.type = Token.Type.closeBlock;
        token.value = token.value[1..$];
      }

      return;
    }

    if(index < tpl.length) {
      token.type = Token.Type.plain;
      pos = tpl[index..$].indexOf("{{");

      if(pos == -1) {
        token.value = tpl[index..$];
      } else {
        token.value = tpl[index..index+pos];
      }

      nextIndex = index + token.value.length;

      if( token.type == Token.Type.plain ) {
        token.value = token.value.stripBeginToken.stripEndToken;
      }
    }
  }

  ///
  Token front() {
    return this.token;
  }

  ///
  bool empty() {
    return index >= tpl.length || index == nextIndex;
  }

  ///
  void popFront() {
    index = nextIndex;
    next();
  }
}

/// It should parse a token value
unittest {
  enum tpl = "{{value}}";

  auto range = TokenRange(tpl);

  range.front.should.equal(Token(Token.Type.value, "value", Properties("")));
}

/// It should parse an helper token
unittest {
  enum tpl = "{{helper value}}";

  auto range = TokenRange(tpl);

  range.front.should.equal(Token(Token.Type.helper, "helper", Properties("value")));
}

/// It should parse block tokens
unittest {
  enum tpl = "{{#if condition}}{{else}}{{/if}}";

  auto range = TokenRange(tpl);

  range.array.should.equal([
    Token(Token.Type.openBlock, "if", Properties("condition")),
    Token(Token.Type.value, "else", Properties("")),
    Token(Token.Type.closeBlock, "if", Properties(""))]);
}

/// It should parse two value tokens
unittest {
  enum tpl = "{{value1}}{{value2}}";

  auto range = TokenRange(tpl);

  range.array.should.equal([
    Token(Token.Type.value, "value1", Properties("")),
    Token(Token.Type.value, "value2", Properties(""))]);
}

/// It should parse value and text tokens
unittest {
  enum tpl = "1{{value1}}2{{value2}}3";

  auto range = TokenRange(tpl);

  range.array.should.equal([
    Token(Token.Type.plain, "1", Properties("")),
    Token(Token.Type.value, "value1", Properties("")),
    Token(Token.Type.plain, "2", Properties("")),
    Token(Token.Type.value, "value2", Properties("")),
    Token(Token.Type.plain, "3", Properties(""))]);
}

///
class TokenLevelRange(T) {
  private {
    T range;
    Token[] items;
  }

  ///
  this(T range) {
    this.range = range;
    next();
  }

  ///
  private void next() {
    if(range.empty) {
      this.items = [ ];
      return;
    }

    auto token = range.front;
    range.popFront;

    this.items = [ token ];

    if(token.type != Token.Type.openBlock) {
      return;
    }

    size_t level = 1;
    while(!range.empty) {
      this.items ~= range.front;

      if(range.front.type == Token.Type.closeBlock && range.front.value == token.value) {
        level--;
      }

      if(range.front.type == Token.Type.openBlock && range.front.value == token.value) {
        level++;
      }

      range.popFront;
      if(level == 0) {
        break;
      }
    }
  }

  ///
  Token[] front() {
    return items;
  }

  ///
  bool empty() {
    return range.empty && items.length == 0;
  }

  ///
  void popFront() {
    next();
  }
}

///
auto tokenLevelRange(T)(T range) {
  return new TokenLevelRange!(T)(range);
}

/// It should return all tokens if there is one level
unittest {
  enum tpl = "1{{a}}2{{b}}3";

  auto range = TokenRange(tpl);
  auto levelRange = tokenLevelRange(range);

  levelRange.array.should.equal([
    [ Token(Token.Type.plain, "1", Properties("")) ],
    [ Token(Token.Type.value, "a", Properties("")) ],
    [ Token(Token.Type.plain, "2", Properties("")) ],
    [ Token(Token.Type.value, "b", Properties("")) ],
    [ Token(Token.Type.plain, "3", Properties("")) ]
  ]);
}

/// It should group the tokens by levels
unittest {
  enum tpl = "1{{value1}}{{#value2}}3{{/value2}}";

  auto range = TokenRange(tpl);
  auto levelRange = tokenLevelRange(range);

  levelRange.array.should.equal([
    [ Token(Token.Type.plain, "1", Properties("")) ],
    [ Token(Token.Type.value, "value1", Properties("")) ],
    [ Token(Token.Type.openBlock, "value2", Properties("")),
        Token(Token.Type.plain, "3", Properties("")),
        Token(Token.Type.closeBlock, "value2", Properties("")) ]
  ]);
}

/// It should group the tokens by levels when the same component is used in the block
unittest {
  enum tpl = "{{#a}}{{#a}}{{#a}}3{{/a}}{{/a}}{{/a}}";

  auto range = TokenRange(tpl);
  auto levelRange = tokenLevelRange(range);

  levelRange.array.should.equal([
    [ Token(Token.Type.openBlock, "a", Properties("")),
        Token(Token.Type.openBlock, "a", Properties("")),
          Token(Token.Type.openBlock, "a", Properties("")),
            Token(Token.Type.plain, "3", Properties("")),
          Token(Token.Type.closeBlock, "a", Properties("")),
        Token(Token.Type.closeBlock, "a", Properties("")),
      Token(Token.Type.closeBlock, "a", Properties("")) ]
  ]);
}

/// It should strip ws from plain tokens
unittest {
  enum tpl = "{{a}}\ntest\n{{a}}";
  auto range = TokenRange(tpl);
  auto levelRange = tokenLevelRange(range);

  levelRange.array.should.equal([
    [ Token(Token.Type.value, "a", Properties("")) ],
    [ Token(Token.Type.plain, "test", Properties("")) ],
    [ Token(Token.Type.value, "a", Properties("")) ]]);
}

///
T evaluate(T,U)(U value, string fieldName) {
  static immutable ignoredMembers = [ __traits(allMembers, Object), "render", "this" ];
  auto pieces = fieldName.splitMemberAccess;

  static foreach (memberName; __traits(allMembers, U)) {{
    static if(__traits(hasMember, U, memberName)) {
      enum protection = __traits(getProtection, __traits(getMember, U, memberName));
    } else {
      enum protection = "";
    }

    static if(protection == "public" && !ignoredMembers.canFind(memberName)) {
      mixin(`alias field = U.` ~ memberName ~ `;`);

      static if (isCallable!(field)) {
        alias FieldType = ReturnType!field;
      } else {
        alias FieldType = typeof(field);
      }

      static if(isArray!FieldType && !isSomeString!FieldType) {
        static if(isBasicType!T || isSomeString!T) {
          if(pieces.length == 2 && pieces[0] == memberName && pieces[1] == "length") {
            mixin(`return value.` ~ memberName ~ `.length.to!(T);`);
          }
        }

        if(pieces.length == 2 && pieces[0] == memberName && pieces[1][0] == '[') {
          auto k = pieces[1][1..$-1].to!size_t;

          static if(__traits(compiles, FieldType.init[0].to!(T))) {
            mixin(`return value.` ~ memberName ~ `[k].to!(T);`);
          }
        }

        if(pieces.length == 1 && pieces[0] == memberName) {
          static if(is(T == FieldType)) {
            mixin(`return value.` ~ memberName ~ `;`);
          } else static if(__traits(compiles, FieldType.init.to!(T))) {
            mixin(`return value.` ~ memberName ~ `.to!(T);`);
          } else {
            throw new Exception("Can't assign `"~fieldName~"` because can't transform " ~ T.stringof ~ " from " ~ FieldType.stringof);
          }
        }
      } else static if((isCallable!(field) && arity!field == 0) || !isCallable!(field)) {
        if(pieces.length == 1 && pieces[0] == memberName) {
          mixin(`auto tmp = value.` ~ memberName ~ `;`);
          static if(is(T == bool)) {
            static if(is(typeof(tmp) == bool)) {
              return tmp;
            } else static if(is(typeof(tmp) == class)) {
              return tmp !is null;
            } else static if(std.traits.isNumeric!(typeof(tmp))) {
              return tmp != 0;
            } else static if(is(typeof(tmp) == string)) {
              return tmp != "";
            } else {
              return true;
            }
          } else static if(__traits(compiles, tmp.to!string.to!T)) {
            return tmp.to!string.to!T;
          } else {
            throw new Exception("Can't evaluate `"~fieldName~"` as `"~T.stringof~"`");
          }
        }
      }
    }
  }}

  return T.init;
}

string[] splitMemberAccess(string memberName) {
  string[] result;

  foreach(item; memberName.split(".")) {
    auto pos = item.indexOf("[");

    if(pos != -1) {
      result ~= item[0..pos];
      result ~= item[pos..$];
    } else {
      result ~= item;
    }
  }

  return result;
}

///
string stripBeginToken(string value) {
  long begin;
  auto pos = value.indexOf("\n");
  auto charPos = getFirstCharPos(value);

  if(charPos != -1 && pos > charPos) {
    return value;
  }

  if(pos >= 0) {
    begin = pos + 1;
  }

  return value[begin..$];
}

/// Remove the white spaces until the first new line
unittest {
  "  \n\n\n".stripBeginToken.should.equal("\n\n");
  "  \r\n\r\n\r\n".stripBeginToken.should.equal("\r\n\r\n");
  " a \n\n\n".stripBeginToken.should.equal(" a \n\n\n");
  " b \r\n\r\n\r\n".stripBeginToken.should.equal(" b \r\n\r\n\r\n");
  "\ntest\n".stripBeginToken.should.equal("test\n");
  "  ".stripBeginToken.should.equal("  ");
}

///
long getFirstCharPos(const string value) {
  foreach(long index, char ch; value) {
    if(ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r') {
      return index;
    }
  }

  return -1;
}

/// Get the position of the first non ws char
unittest {
  "  \r\n\r\n\r\n".getFirstCharPos.should.equal(-1);
  "  \r\n\t".getFirstCharPos.should.equal(-1);
  " b \r\n\r\n\r\n".getFirstCharPos.should.equal(1);
}


///
string stripEndToken(string value) {
  long end = value.length;
  auto pos = value.lastIndexOf("\n");
  if(value.lastIndexOf("\r") == pos - 1) {
    pos--;
  }

  auto charPos = getLastCharPos(value);

  if(charPos != -1 && pos < charPos) {
    return value;
  }

  if(pos >= 0) {
    end = pos;
  }

  return value[0..end];
}

/// Remove the white spaces after the last new line
unittest {
  "  \n\n\n  ".stripEndToken.should.equal("  \n\n");
  "  \r\n\r\n\r\n  ".stripEndToken.should.equal("  \r\n\r\n");
  " a \n\n\n a ".stripEndToken.should.equal(" a \n\n\n a ");
  " b \r\n\r\n\r\n a ".stripEndToken.should.equal(" b \r\n\r\n\r\n a ");
  "\ntest\n".stripEndToken.should.equal("\ntest");
  "  ".stripEndToken.should.equal("  ");
}


///
long getLastCharPos(const string value) {
  foreach_reverse(long index, char ch; value) {
    if(ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r') {
      return index;
    }
  }

  return -1;
}

/// Get the position of the last non ws char
unittest {
  "  \r\n\r\n\r\n".getLastCharPos.should.equal(-1);
  "  \r\n\t".getLastCharPos.should.equal(-1);
  " a \r\n\r\n\r\n b ".getLastCharPos.should.equal(10);
}
