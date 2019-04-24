module handlebars.components.scope_;

import handlebars.components.base;

import std.string;

/// Component that will handle the if blocks
class ScopeComponent : HbsComponent!"" {

  ///
  enum ComponentName = "scope";

  private {
    string propertyName;
    string localName;
    string index;
    string indexName;
  }

  ///
  this(string propertyName, string localName, string index, string indexName) {
    this.propertyName = propertyName;
    this.localName = localName;
    this.index = index;
    this.indexName = indexName;
  }

  ///
  string render(Component, Components...)() {
    Token[] localContent;

    foreach(item; this.content) {
      Token token = copy(item);

      if(token.value == localName) {
        token.value = propertyName ~ "[" ~ index ~ "]";
      }

      if(token.value.indexOf(localName ~ ".") == 0) {
        auto pieces = token.value.split(".");
        token.value = propertyName ~ "[" ~ index ~ "]." ~ pieces[1..$].join(".");
      }

      if(token.value == indexName) {
        token.value = index;
        token.type = Token.Type.plain;
      }

      foreach(ref property; token.properties.list) {
        if(property.isEvaluated) {
          continue;
        }

        if(property.value == localName) {
          property.value = propertyName ~ "[" ~ index ~ "]";
        }

        if(property.value == indexName) {
          property.value = index;
          property.isEvaluated = true;
        }
      }

      foreach(ref property; token.properties.hash) {
        if(property.isEvaluated) {
          continue;
        }

        if(property.value == localName) {
          property.value = propertyName ~ "[" ~ index ~ "]";
        }

        if(property.value == indexName) {
          property.value = index;
          property.isEvaluated = true;
        }
      }

      localContent ~= token;
    }

    return lifecycle.yield(localContent);
  }
}

///
Token copy(Token item) {
  Token token;

  token.value = item.value;
  token.type = item.type;

  token.properties.localName = item.properties.localName;
  token.properties.indexName = item.properties.indexName;
  token.properties.name = item.properties.name;

  foreach(property; item.properties.list) {
    token.properties.list ~= Properties.Property(property.value, property.isEvaluated);
  }

  foreach(key, property; item.properties.hash) {
    token.properties.hash[key] = Properties.Property(property.value, property.isEvaluated);
  }

  return token;
}
