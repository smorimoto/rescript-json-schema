// Generated by ReScript, PLEASE EDIT WITH CARE

import * as Curry from "rescript/lib/es6/curry.js";
import * as Json5 from "json5";
import * as React from "react";
import * as JSONSchema from "rescript-json-schema/src/JSONSchema.bs.mjs";
import * as Core__Option from "@rescript/core/src/Core__Option.bs.mjs";
import * as S$RescriptStruct from "rescript-struct/src/S.bs.mjs";
import CopyToClipboard from "copy-to-clipboard";
import * as JsxRuntime from "react/jsx-runtime";
import * as Caml_js_exceptions from "rescript/lib/es6/caml_js_exceptions.js";

function App(props) {
  var match = React.useState(function () {
        return "{\n  \"$schema\": \"http://json-schema.org/draft-07/schema#\",\n  \"type\": \"object\",\n  \"properties\": {\n    \"Age\": {\n      \"deprecated\": true,\n      \"description\": \"Will be removed in APIv2\",\n      \"type\": \"integer\"\n    },\n    \"Id\": { \"type\": \"number\" },\n    \"IsApproved\": {\n      \"anyOf\": [\n        {\n          \"const\": \"Yes\",\n          \"type\": \"string\"\n        },\n        {\n          \"const\": \"No\",\n          \"type\": \"string\"\n        }\n      ]\n    },\n    \"Tags\": {\n      \"items\": { \"type\": \"string\" },\n      \"type\": \"array\"\n    }\n  },\n  \"required\": [\"Id\", \"IsApproved\"],\n  \"additionalProperties\": true\n}";
      });
  var setJson = match[1];
  var json = match[0];
  var match$1 = React.useState(function () {
        return "";
      });
  var setInlineStruct = match$1[1];
  var inlinedStruct = match$1[0];
  var match$2 = React.useState(function () {
        return "";
      });
  var setErrors = match$2[1];
  var errors = match$2[0];
  React.useEffect((function () {
          ((async function (param) {
                  try {
                    var parsed = Json5.default.parse(json);
                    Curry._1(setErrors, (function (param) {
                            return "";
                          }));
                    Curry._1(setInlineStruct, (function (param) {
                            return S$RescriptStruct.inline(JSONSchema.toStruct(parsed));
                          }));
                    return ;
                  }
                  catch (raw_exn){
                    var exn = Caml_js_exceptions.internalToOCamlException(raw_exn);
                    return Curry._1(setErrors, (function (param) {
                                  return "Errors:\n" + Core__Option.getWithDefault(Core__Option.flatMap(Caml_js_exceptions.as_js_exn(exn), (function (prim) {
                                                    return prim.message;
                                                  })), "Unknown error") + "";
                                }));
                  }
                })(undefined));
        }), [json]);
  var tmp = errors === "" ? inlinedStruct : errors;
  return JsxRuntime.jsxs(JsxRuntime.Fragment, {
              children: [
                JsxRuntime.jsx("h1", {
                      children: "ReScript JSON Schema Online"
                    }),
                JsxRuntime.jsxs("div", {
                      children: [
                        JsxRuntime.jsxs("div", {
                              children: [
                                JsxRuntime.jsx("b", {
                                      children: "Json Schema"
                                    }),
                                JsxRuntime.jsx("textarea", {
                                      style: {
                                        height: "400px",
                                        width: "auto"
                                      },
                                      value: json,
                                      onChange: (function (e) {
                                          Curry._1(setJson, e.target.value);
                                        })
                                    }),
                                JsxRuntime.jsx("button", {
                                      children: "Format",
                                      style: {
                                        width: "100%"
                                      },
                                      disabled: errors !== "",
                                      onClick: (function (param) {
                                          try {
                                            return Curry._1(setJson, (function (param) {
                                                          return JSON.stringify(Json5.default.parse(json), null, 2);
                                                        }));
                                          }
                                          catch (raw_exn){
                                            var exn = Caml_js_exceptions.internalToOCamlException(raw_exn);
                                            return Curry._1(setErrors, (function (param) {
                                                          return "Errors:\n" + Core__Option.getWithDefault(Core__Option.flatMap(Caml_js_exceptions.as_js_exn(exn), (function (prim) {
                                                                            return prim.message;
                                                                          })), "Unknown error") + "";
                                                        }));
                                          }
                                        })
                                    })
                              ],
                              style: {
                                border: "1px solid grey",
                                display: "flex",
                                margin: "10px",
                                padding: "10px",
                                flexDirection: "column",
                                flexGrow: "1"
                              }
                            }),
                        JsxRuntime.jsxs("div", {
                              children: [
                                JsxRuntime.jsx("b", {
                                      children: "Result"
                                    }),
                                JsxRuntime.jsx("textarea", {
                                      style: {
                                        color: errors === "" ? "black" : "red",
                                        height: "476px",
                                        width: "auto"
                                      },
                                      readOnly: true,
                                      value: tmp
                                    }),
                                JsxRuntime.jsx("button", {
                                      children: "Copy",
                                      style: {
                                        width: "100%"
                                      },
                                      disabled: errors !== "",
                                      onClick: (function (param) {
                                          CopyToClipboard(inlinedStruct);
                                        })
                                    })
                              ],
                              style: {
                                border: "1px solid grey",
                                display: "flex",
                                margin: "10px",
                                padding: "10px",
                                flexDirection: "column",
                                flexGrow: "1"
                              }
                            })
                      ],
                      style: {
                        display: "flex",
                        justifyContent: "flex-grow"
                      }
                    }),
                JsxRuntime.jsx("a", {
                      children: "Get the CLI NPM package here",
                      href: "https://npmjs.com/package/rescript-json-schema"
                    }),
                JsxRuntime.jsx("br", {}),
                JsxRuntime.jsx("a", {
                      children: "Log an issue, open a feature PR or just leave a ⭐ here ^^",
                      href: "https://github.com/dzakh/rescript-json-schema"
                    })
              ]
            });
}

var make = App;

export {
  make ,
}
/* json5 Not a pure module */
