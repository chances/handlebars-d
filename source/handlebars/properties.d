module handlebars.properties;

import std.string;
import std.traits;
import std.conv;

version(unittest) {
  import fluent.asserts;
}

///
struct Properties {
  struct Property {
    string value;
    bool isEvaluated;

    this(string value, bool isEvaluated) {
      this.value = value;
      this.isEvaluated = isEvaluated;
    }

    this(string value) {
      if(value == "") {
        return;
      }

      if(value[0] == '"' || value[0] == '\'') {
        this.value = value[1..$-1];
        this.isEvaluated = true;
        return;
      }

      if(isNumeric(value)) {
        this.value = value;
        this.isEvaluated = true;
        return;
      }

      if(value == "true" || value == "false") {
        this.value = value;
        this.isEvaluated = true;
        return;
      }

      this.value = value;
      this.isEvaluated = false;
    }

    T get(T)() if (is(T == string)) {
      return value;
    }

    T get(T)() if (isBuiltinType!T && !is(T == string)) {
      static if(__traits(compiles, this.value.to!T)) {
        return this.value.to!T;
      } else {
        throw new Exception("Can't get `"~value~"` as `"~T.stringof~"`");
      }
    }

    ///
    string toParam() {
      if(isEvaluated) {
        if(value == "true" || value == "false") {
          return value;
        }

        return `"` ~ value ~ `"`;
      }

      return "controller." ~ value;
    }
  }

  ///
  Property[] list;

  ///
  Property[string] hash;

  string localName;
  string indexName;
  string name;

  this(string value) {
    while(value.length > 0) {
      auto pos = value.breakIndex;
      auto item = value[0..pos];
      auto eqPos = item.indexOf("=");

      if(eqPos == -1) {
        list ~= Property(item);
      } else {
        auto key = item[0..eqPos];
        auto val = item[eqPos+1..$];

        hash[key] = Property(val);
      }

      value = value[pos..$].strip;

    }

    if(list.length == 3 && !list[0].isEvaluated && list[1].value == "as" && list[2].value[0] == '|') {
      name = list[0].value;
      auto localProperties = Properties(list[2].value.replace("|", "").strip);
      localName = localProperties.list[0].value;

      if(localProperties.list.length == 2) {
        indexName = localProperties.list[1].value;
      }

      list = [];
    }
  }
}

/// parse a list of string properties
unittest {
  Properties(`"a"  "b"`).list.should.equal([
    Properties.Property("a", true),
    Properties.Property("b", true)]);
}

/// parse a list of string with spaces properties
unittest {
  Properties(`"a b c"  "c d e"`).list.should.equal([
    Properties.Property("a b c", true),
    Properties.Property("c d e", true)]);
}

/// parse a list of variables with spaces properties
unittest {
  Properties(`a 1 c  "c d e"`).list.should.equal([
    Properties.Property("a", false),
    Properties.Property("1", true),
    Properties.Property("c", false),
    Properties.Property("c d e", true)]);
}

/// parse a list of attributes with spaces properties
unittest {
  Properties(`a=1 b=value`).hash["a"]
    .should.equal(Properties.Property("1", true));

  Properties(`a=1 b=value`).hash["b"]
    .should.equal(Properties.Property("value", false));
}

/// parse each properties
unittest {
  Properties(`list as |item|`).name.should.equal("list");
  Properties(`list as |item|`).localName.should.equal("item");
  Properties(`list as |item|`).indexName.should.equal("");


  Properties(`list as | item index |`).name.should.equal("list");
  Properties(`list as | item index |`).localName.should.equal("item");
  Properties(`list as | item index |`).indexName.should.equal("index");
}

///
size_t breakIndex(string value) {
  size_t pos = value.length;

  if(value.length == 0) {
    return 0;
  }

  if(value[0] == '"' || value[0] == '\'' || value[0] == '|') {
    auto tmp = value[1..$];

    while(tmp.length > 0) {
      auto endPos = tmp.indexOf(value[0]);

      if(tmp.length > 1 && tmp[endPos - 1] != '\\') {
        tmp = tmp[endPos+1..$];
        break;
      }

      tmp = tmp[endPos+1..$];
    }

    return value.length - tmp.length;
  }

  foreach(token; [ " ", "\t", "\n" ]) {
    auto tmp = value.indexOf(token) ;

    if(tmp < pos) {
      pos = tmp;
    }
  }

  return pos;
}

/// break index with no breaks should return the length of the string
unittest {
  "".breakIndex.should.equal(0);
  "abc".breakIndex.should.equal(3);
}

/// break index with one break should return the position of the next item
unittest {
  "a b".breakIndex.should.equal(1);
  "a\tb".breakIndex.should.equal(1);
  "a\nb".breakIndex.should.equal(1);
  `"abc" "def"`.breakIndex.should.equal(5);
  `"a c" "def"`.breakIndex.should.equal(5);
  `'a c' "def"`.breakIndex.should.equal(5);
}

/// break index with escaped strings
unittest {
  `"a\"c" "def"`.breakIndex.should.equal(6);
  `'a\'c' "def"`.breakIndex.should.equal(6);
}

/// break index with bar string
unittest {
  `| a  b |`.breakIndex.should.equal(8);
}
