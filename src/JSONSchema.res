@@uncurried

%%private(external magic: 'a => 'b = "%identity")

module Error = {
  type rec t = {code: code, mutable path: array<string>}
  and code =
    | UnsupportedNestedOptional
    | UnsupportedRootOptional
    | UnsupportedOptionalItem(string)
    | UnsupportedStruct(string)
    | DefaultDestructingFailed({destructingErrorMessage: string})

  exception Exception(t)

  let raise = code => {
    raise(Exception({code, path: []}))
  }

  module UnsupportedOptionalItem = {
    let raise = struct => {
      raise(UnsupportedOptionalItem(struct->S.name))
    }
  }

  module UnsupportedStruct = {
    let raise = struct => {
      raise(UnsupportedStruct(struct->S.name))
    }
  }

  let pathToText = path => {
    switch path {
    | [] => "root"
    | _ => path->Js.Array2.map(pathItem => `["${pathItem}"]`)->Js.Array2.joinWith("")
    }
  }

  let prependLocation = (error, location) => {
    error.path = [location]->Js.Array2.concat(error.path)
    error
  }

  let toString = error => {
    let pathText = error.path->pathToText
    let reason = switch error.code {
    | UnsupportedRootOptional => `Optional struct is not supported at root`
    | UnsupportedNestedOptional => `Optional struct is not supported inside the Option struct`
    | UnsupportedOptionalItem(structName) =>
      `Optional struct is not supported as ${structName} item`
    | UnsupportedStruct(structName) => `The ${structName} struct is not supported`
    | DefaultDestructingFailed({destructingErrorMessage}) =>
      `Couldn't destruct default value. Error: ${destructingErrorMessage}`
    }
    `[ReScript JSON Schema] Failed converting at ${pathText}. Reason: ${reason}`
  }
}

include JSONSchema7

@val
external merge: (@as(json`{}`) _, t, t) => t = "Object.assign"

let schemaExtendMetadataId: S.Metadata.Id.t<t> = S.Metadata.Id.make(
  ~namespace="rescript-json-schema",
  ~name="schemaExtend",
)

let isOptionalStruct = struct =>
  switch struct->S.classify {
  | Option(_) => true
  | _ => false
  }

let rec makeStructSchema:
  type value. S.t<value> => t =
  struct => {
    let schema: Mutable.t = {}
    switch struct->S.classify {
    | S.String =>
      schema.type_ = Some(Arrayable.single(#string))
      struct
      ->S.String.refinements
      ->Js.Array2.forEach(refinement => {
        switch refinement {
        | {kind: Email} => schema.format = Some("email")
        | {kind: Url} => schema.format = Some("uri")
        | {kind: Uuid} => schema.format = Some("uuid")
        | {kind: Datetime} => schema.format = Some("date-time")
        | {kind: Cuid} => ()
        | {kind: Length({length})} => {
            schema.minLength = Some(length)
            schema.maxLength = Some(length)
          }
        | {kind: Max({length})} => schema.maxLength = Some(length)
        | {kind: Min({length})} => schema.minLength = Some(length)
        | {kind: Pattern({re})} => schema.pattern = Some(re->Js.String2.make)
        }
      })
    | S.Int => {
        schema.type_ = Some(Arrayable.single(#integer))
        struct
        ->S.Int.refinements
        ->Js.Array2.forEach(refinement => {
          switch refinement {
          | {kind: Port} => ()
          | {kind: Max({value})} => schema.maximum = Some(value->Js.Int.toFloat)
          | {kind: Min({value})} => schema.minimum = Some(value->Js.Int.toFloat)
          }
        })
      }
    | S.Bool => schema.type_ = Some(Arrayable.single(#boolean))
    | S.Float => {
        schema.type_ = Some(Arrayable.single(#number))
        struct
        ->S.Float.refinements
        ->Js.Array2.forEach(refinement => {
          switch refinement {
          | {kind: Max({value})} => schema.maximum = Some(value)
          | {kind: Min({value})} => schema.minimum = Some(value)
          }
        })
      }
    | S.Array(childStruct) => {
        if childStruct->isOptionalStruct {
          Error.UnsupportedOptionalItem.raise(struct)
        }
        schema.items = Some(Arrayable.single(Definition.schema(makeStructSchema(childStruct))))
        schema.type_ = Some(Arrayable.single(#array))
        struct
        ->S.Array.refinements
        ->Js.Array2.forEach(refinement => {
          switch refinement {
          | {kind: Max({length})} => schema.maxItems = Some(length)
          | {kind: Min({length})} => schema.minItems = Some(length)
          | {kind: Length({length})} => {
              schema.maxItems = Some(length)
              schema.minItems = Some(length)
            }
          }
        })
      }

    | S.Tuple(childStructs) => {
        let items = childStructs->Js.Array2.mapi((childStruct, idx) => {
          try {
            if childStruct->isOptionalStruct {
              Error.UnsupportedOptionalItem.raise(struct)
            } else {
              Definition.schema(makeStructSchema(childStruct))
            }
          } catch {
          | Error.Exception(error) =>
            raise(Error.Exception(error->Error.prependLocation(idx->Js.Int.toString)))
          }
        })
        let itemsNumber = items->Js.Array2.length

        schema.items = Some(Arrayable.array(items))
        schema.type_ = Some(Arrayable.single(#array))
        schema.minItems = Some(itemsNumber)
        schema.maxItems = Some(itemsNumber)
      }

    | S.Union(childStructs) => {
        let items = childStructs->Js.Array2.map(childStruct => {
          if childStruct->isOptionalStruct {
            Error.UnsupportedOptionalItem.raise(struct)
          } else {
            Definition.schema(makeStructSchema(childStruct))
          }
        })
        schema.anyOf = Some(items)
      }

    | S.Option(childStruct) => {
        if childStruct->isOptionalStruct {
          Error.raise(UnsupportedNestedOptional)
        }

        let childSchema = makeStructSchema(childStruct)
        schema->Mutable.mixin(childSchema)

        switch struct->S.Option.default {
        | Some(default) =>
          let defaultValue = switch default {
          | Value(v) => v
          | Callback(cb) => cb()
          }
          switch Some(defaultValue)
          ->(magic: option<unknown> => unknown)
          ->S.serializeWith(childStruct) {
          | Error(destructingError) =>
            Error.raise(
              DefaultDestructingFailed({
                destructingErrorMessage: destructingError->S.Error.message,
              }),
            )
          | Ok(destructedValue) => schema.default = Some(destructedValue)
          }
        | None => ()
        }
      }
    | S.Object({fields, fieldNames, unknownKeys}) => {
        let properties = Js.Dict.empty()
        let required = []
        fieldNames->Js.Array2.forEach(fieldName => {
          let fieldStruct = fields->Js.Dict.unsafeGet(fieldName)
          let fieldSchema = try {
            makeStructSchema(fieldStruct)
          } catch {
          | Error.Exception(error) =>
            raise(Error.Exception(error->Error.prependLocation(fieldName)))
          }
          if fieldStruct->isOptionalStruct->not {
            required->Js.Array2.push(fieldName)->ignore
          }
          properties->Js.Dict.set(fieldName, Definition.schema(fieldSchema))
        })
        let additionalProperties = switch unknownKeys {
        | Strict => false
        | Strip => true
        }

        schema.type_ = Some(Arrayable.single(#object))
        schema.properties = Some(properties)
        schema.additionalProperties = Some(Definition.boolean(additionalProperties))
        switch required {
        | [] => ()
        | required => schema.required = Some(required)
        }
      }
    | S.JSON
    | S.Unknown => ()
    | S.Null(childStruct) =>
      schema.anyOf = Some([
        Definition.schema(makeStructSchema(childStruct)),
        Definition.schema({
          type_: Arrayable.single(#null),
        }),
      ])

    | S.Never => schema.not = Some(Definition.schema({}))
    | S.Literal(Boolean(value)) => {
        schema.type_ = Some(Arrayable.single(#boolean))
        schema.const = Some(Js.Json.boolean(value))
      }
    | S.Literal(Number(value)) => {
        let isInt = mod_float(value, 1.) === 0.
        schema.type_ = Some(Arrayable.single(isInt ? #integer : #number))
        schema.const = Some(Js.Json.number(value))
      }
    | S.Literal(String(value)) => {
        schema.type_ = Some(Arrayable.single(#string))
        schema.const = Some(Js.Json.string(value))
      }
    | S.Literal(Null) => schema.type_ = Some(Arrayable.single(#null))
    | S.Literal(Undefined)
    | S.Literal(BigInt(_))
    | S.Literal(Function(_))
    | S.Literal(Array(_))
    | S.Literal(Dict(_))
    | S.Literal(Symbol(_))
    | S.Literal(Object(_))
    | S.Literal(NaN) =>
      Error.UnsupportedStruct.raise(struct)
    | S.Dict(childStruct) =>
      if childStruct->isOptionalStruct {
        Error.UnsupportedOptionalItem.raise(struct)
      }

      schema.type_ = Some(Arrayable.single(#object))
      schema.additionalProperties = Some(Definition.schema(makeStructSchema(childStruct)))
    }

    switch struct->S.description {
    | Some(m) => schema.description = Some(m)
    | None => ()
    }

    switch struct->S.deprecation {
    | Some(message) =>
      schema->Mutable.mixin({"deprecated": true, "description": message}->(magic: 'a => t))
    | None => ()
    }

    switch struct->S.Metadata.get(~id=schemaExtendMetadataId) {
    | Some(metadataRawSchema) => schema->Mutable.mixin(metadataRawSchema)
    | None => ()
    }

    schema->Mutable.toReadOnly
  }

let make = struct => {
  try {
    if struct->isOptionalStruct {
      Error.raise(UnsupportedRootOptional)
    } else {
      let schema = makeStructSchema(struct)->Mutable.fromReadOnly
      schema.schema = Some("http://json-schema.org/draft-07/schema#")
      Ok(schema->Mutable.toReadOnly)
    }
  } catch {
  | Error.Exception(error) => Error(error->Error.toString)
  }
}

let extend = (struct, schema) => {
  struct->S.Metadata.set(
    ~id=schemaExtendMetadataId,
    switch struct->S.Metadata.get(~id=schemaExtendMetadataId) {
    | Some(existingSchemaExtend) => merge(existingSchemaExtend, schema)
    | None => schema
    },
  )
}

let castAnyStructToJsonStruct = (magic: S.t<'any> => S.t<Js.Json.t>)

@inline
let primitiveToStruct = primitive => {
  S.literal(primitive)->castAnyStructToJsonStruct
}

let toIntStruct = (schema: t) => {
  let struct = S.int
  // TODO: Support schema.multipleOf when it's in rescript-struct
  // if (typeof schema.multipleOf === "number" && schema.multipleOf !== 1) {
  //  r += `.multipleOf(${schema.multipleOf})`;
  // }
  let struct = switch schema {
  | {minimum} => struct->S.Int.min(minimum->Belt.Float.toInt)
  | {exclusiveMinimum} => struct->S.Int.min((exclusiveMinimum +. 1.)->Belt.Float.toInt)
  | _ => struct
  }
  let struct = switch schema {
  | {maximum} => struct->S.Int.max(maximum->Belt.Float.toInt)
  | {exclusiveMinimum} => struct->S.Int.max((exclusiveMinimum -. 1.)->Belt.Float.toInt)
  | _ => struct
  }
  struct->castAnyStructToJsonStruct
}

let definitionToDefaultValue = definition =>
  switch definition->Definition.classify {
  | Schema(s) => s.default
  | Boolean(_) => None
  }

let rec toStruct = (schema: t) => {
  let definitionToStruct = definition =>
    switch definition->Definition.classify {
    | Schema(s) => s->toStruct
    | Boolean(_) => S.json
    }

  let struct = switch schema {
  | _ if (schema->(magic: t => {..}))["nullable"] =>
    S.null(
      schema->merge({"nullable": false}->(magic: {..} => t))->toStruct,
    )->castAnyStructToJsonStruct
  | {type_} if type_ === Arrayable.single(#object) =>
    let struct = switch schema.properties {
    | Some(properties) =>
      let struct = S.object(s =>
        properties
        ->Js.Dict.entries
        ->Js.Array2.map(((key, property)) => {
          let propertyStruct = property->definitionToStruct
          let propertyStruct = switch schema.required {
          | Some(r) if r->Js.Array2.includes(key) => propertyStruct
          | _ =>
            switch property->definitionToDefaultValue {
            | Some(defaultValue) =>
              propertyStruct->S.option->S.Option.getOr(defaultValue)->castAnyStructToJsonStruct
            | None => propertyStruct->S.option->castAnyStructToJsonStruct
            }
          }
          (key, s.field(key, propertyStruct))
        })
        ->Js.Dict.fromArray
      )
      let struct = switch schema {
      | {additionalProperties} if additionalProperties === Definition.boolean(false) =>
        struct->S.Object.strict
      | _ => struct
      }
      struct->castAnyStructToJsonStruct
    | None =>
      switch schema.additionalProperties {
      | Some(additionalProperties) =>
        switch additionalProperties->Definition.classify {
        | Boolean(true) => S.dict(S.json)->castAnyStructToJsonStruct
        | Boolean(false) => S.object(_ => ())->S.Object.strict->castAnyStructToJsonStruct
        | Schema(s) => S.dict(s->toStruct)->castAnyStructToJsonStruct
        }
      | None => S.object(_ => ())->castAnyStructToJsonStruct
      }
    }

    // TODO: schema.anyOf and schema.oneOf support
    struct
  | {type_} if type_ === Arrayable.single(#array) => {
      let struct = switch schema.items {
      | Some(items) =>
        switch items->Arrayable.classify {
        | Single(single) => S.array(single->definitionToStruct)
        | Array(array) =>
          S.tuple(s => array->Js.Array2.mapi((d, idx) => s.item(idx, d->definitionToStruct)))
        }
      | None => S.array(S.json)
      }
      let struct = switch schema.minItems {
      | Some(min) => struct->S.Array.min(min)
      | _ => struct
      }
      let struct = switch schema.maxItems {
      | Some(max) => struct->S.Array.max(max)
      | _ => struct
      }
      struct->castAnyStructToJsonStruct
    }
  | {anyOf: []} => S.json
  | {anyOf: [d]} => d->definitionToStruct
  | {anyOf: definitions} => S.union(definitions->Js.Array2.map(definitionToStruct))
  | {allOf: []} => S.json
  | {allOf: [d]} => d->definitionToStruct
  | {allOf: definitions} =>
    S.json->S.refine(s => data => {
      definitions->Js.Array2.forEach(d => {
        switch data->S.parseWith(d->definitionToStruct) {
        | Ok(_) => ()
        | Error(_) => s.fail("Should pass for all schemas of the allOf property.")
        }
      })
    })
  | {oneOf: []} => S.json
  | {oneOf: [d]} => d->definitionToStruct
  | {oneOf: definitions} =>
    S.json->S.refine(s => data => {
      let hasOneValidRef = ref(false)
      definitions->Js.Array2.forEach(d => {
        switch data->S.parseWith(d->definitionToStruct) {
        | Ok(_) if hasOneValidRef.contents =>
          s.fail("Should pass single schema according to the oneOf property.")
        | Ok(_) => hasOneValidRef.contents = true
        | Error(_) => ()
        }
      })
      if hasOneValidRef.contents->not {
        s.fail("Should pass at least one schema according to the oneOf property.")
      }
    })
  | {not} =>
    S.json->S.refine(s => data =>
      switch data->S.parseWith(not->definitionToStruct) {
      | Ok(_) => s.fail("Should NOT be valid against schema in the not property.")
      | Error(_) => ()
      })
  // needs to come before primitives
  | {enum: []} => S.json
  | {enum: [p]} => p->primitiveToStruct
  | {enum: primitives} =>
    S.union(primitives->Js.Array2.map(primitiveToStruct))->castAnyStructToJsonStruct
  | {const} => const->primitiveToStruct
  | {type_} if type_->Arrayable.isArray =>
    let types = type_->(magic: Arrayable.t<'a> => array<'a>)
    S.union(
      types->Js.Array2.map(type_ => {
        schema->merge({type_: Arrayable.single(type_)})->toStruct
      }),
    )
  | {type_} if type_ === Arrayable.single(#string) =>
    let struct = S.string
    let struct = switch schema {
    | {pattern} => struct->S.String.pattern(Js.Re.fromString(pattern))
    | _ => struct
    }

    let struct = switch schema {
    | {minLength} => struct->S.String.min(minLength)
    | _ => struct
    }
    let struct = switch schema {
    | {maxLength} => struct->S.String.max(maxLength)
    | _ => struct
    }
    switch schema {
    | {format: "email"} => struct->S.String.email->castAnyStructToJsonStruct
    | {format: "uri"} => struct->S.String.url->castAnyStructToJsonStruct
    | {format: "uuid"} => struct->S.String.uuid->castAnyStructToJsonStruct
    | {format: "date-time"} => struct->S.String.datetime->castAnyStructToJsonStruct
    | _ => struct->castAnyStructToJsonStruct
    }

  | {type_} if type_ === Arrayable.single(#integer) => schema->toIntStruct
  | {type_, format: "int64"} if type_ === Arrayable.single(#number) => schema->toIntStruct
  | {type_, multipleOf: 1.} if type_ === Arrayable.single(#number) => schema->toIntStruct
  | {type_} if type_ === Arrayable.single(#number) => {
      let struct = S.float
      let struct = switch schema {
      | {minimum} => struct->S.Float.min(minimum)
      | {exclusiveMinimum} => struct->S.Float.min(exclusiveMinimum +. 1.)
      | _ => struct
      }
      let struct = switch schema {
      | {maximum} => struct->S.Float.max(maximum)
      | {exclusiveMinimum} => struct->S.Float.max(exclusiveMinimum -. 1.)
      | _ => struct
      }
      struct->castAnyStructToJsonStruct
    }
  | {type_} if type_ === Arrayable.single(#boolean) => S.bool->castAnyStructToJsonStruct
  | {type_} if type_ === Arrayable.single(#null) =>
    S.literal(%raw(`null`))->castAnyStructToJsonStruct
  | {if_, then, else_} => {
      let ifStruct = if_->definitionToStruct
      let thenStruct = then->definitionToStruct
      let elseStruct = else_->definitionToStruct
      S.json->S.refine(s => data => {
        let result = switch data->S.parseWith(ifStruct) {
        | Ok(_) => data->S.parseWith(thenStruct)
        | Error(_) => data->S.parseWith(elseStruct)
        }
        switch result {
        | Ok(_) => ()
        | Error(e) => s.failWithError(e)
        }
      })
    }
  | _ => S.json
  }

  let struct = switch schema {
  | {description} => struct->S.describe(description)
  | _ => struct
  }

  let struct = switch schema {
  | {description} => struct->S.describe(description)
  | _ => struct
  }

  struct
}
