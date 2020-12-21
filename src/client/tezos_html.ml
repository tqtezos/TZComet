open Import

module Block_explorer = struct
  type vendor = Smartpy | Bcd

  let all_vendors = [Smartpy; Bcd]

  let kt1_url vendor kt1 =
    match vendor with
    | Smartpy -> Fmt.str "https://smartpy.io/dev/explorer.html?address=%s" kt1
    | Bcd -> Fmt.str "https://better-call.dev/search?text=%s" kt1

  let vendor_show_name = function Smartpy -> "SmartPy" | Bcd -> "BCD"

  let kt1_display kt1 =
    let open Meta_html in
    let sep () = t ", " in
    Bootstrap.monospace (bt kt1)
    %% small
         (parens
            (list
               (oxfordize_list ~map:Fn.id ~sep ~last_sep:sep
                  (List.map all_vendors ~f:(fun v ->
                       let target = kt1_url v kt1 in
                       link ~target (t (vendor_show_name v)))))))
end

let uri_parsing_error err =
  let open Meta_html in
  let open Tezos_contract_metadata.Metadata_uri.Parsing_error in
  let details =
    let sha256_host_advice =
      t "The host should look like:"
      %% ct "0x5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
      % t "." in
    let scheme_advice =
      t "The URI should start with one of:"
      %% list
           (oxfordize_list
              ["tezos-storage"; "http"; "https"; "sha256"; "ipfs"]
              ~map:(fun sch -> Fmt.kstr ct "%s:" sch)
              ~sep:(fun () -> t ", ")
              ~last_sep:(fun () -> t ", or "))
      % t "." in
    match err.error_kind with
    | Wrong_scheme None -> t "Missing URI scheme. " % scheme_advice
    | Wrong_scheme (Some scheme) ->
        t "Unknown URI scheme: " % ct scheme % t "." %% scheme_advice
    | Missing_cid_for_ipfs ->
        t "Missing content identifier in IPFS URI, it should be the host."
    | Wrong_tezos_storage_host str ->
        t "Cannot parse the “host” part of the URI: "
        %% ct str % t ", should look like " %% ct "<network>.<address>"
        % t " or just" %% ct "<address>"
    | Forbidden_slash_in_tezos_storage_path path ->
        t "For " %% ct "tezos-storage"
        % t " URIs, the “path” cannot contain any "
        % ct "/"
        % t " (“slash”) character: "
        % ct path
    | Missing_host_for_hash_uri `Sha256 ->
        t "Missing “host” in " % ct "sha256://" % t " URI. "
        %% sha256_host_advice
    | Wrong_hex_format_for_hash {hash= `Sha256; host; message} ->
        t "Failed to parse the “host” "
        %% ct host % t " in this " %% ct "sha256://" % t " URI: " % t message
        % t " → " %% sha256_host_advice in
  let exploded_uri =
    let u = Uri.of_string err.input in
    let item name opt =
      it name % t ": " % match opt with None -> t "<empty>" | Some s -> ct s
    in
    let item_some name s = item name (Some s) in
    t "The URI is understood this way: "
    % itemize
        [ item "Scheme" (Uri.scheme u); item "Host" (Uri.host u)
        ; item "User-info" (Uri.userinfo u)
        ; item "Port" (Uri.port u |> Option.map ~f:Int.to_string)
        ; item_some "Path" (Uri.path u); item "Query" (Uri.verbatim_query u)
        ; item "Fragment" (Uri.fragment u) ] in
  t "Failed to parse URI:" %% ct err.input % t ":"
  % itemize [details; exploded_uri]

let json_encoding_error : Errors_html.handler =
  let open Meta_html in
  let open Json_encoding in
  let quote s = Fmt.kstr ct "%S" s in
  let rec go = function
    | Cannot_destruct ([], e) -> go e
    | Cannot_destruct (path, e) ->
        let p =
          Fmt.kstr ct "%a"
            (Json_query.print_path_as_json_path ~wildcards:true)
            path in
        t "At path" %% p % t ":" %% go e
    | Unexpected (u, e) ->
        let article s =
          (* 90% heuristic :) *)
          match s.[0] with
          | 'a' | 'e' | 'i' | 'o' -> t "an"
          | _ -> t "a"
          | exception _ -> t "something" in
        let with_article s = article s %% it s in
        t "Expecting" %% with_article e %% t "but got" %% with_article u
    | No_case_matched l ->
        t "No case matched expectations:" %% itemize (List.map ~f:go l)
    | Bad_array_size (u, e) ->
        Fmt.kstr t "Expecting array of size %d but got %d" e u
    | Missing_field field -> t "Missing field" %% quote field
    | Unexpected_field field -> t "Unexpected field" %% quote field
    | Bad_schema e -> t "Bad schema:" %% go e
    | e -> raise e in
  fun e -> match go e with m -> Some (m % t ".", []) | exception _ -> None

let simple_exns_handler : Errors_html.handler =
  let open Meta_html in
  let some m = Some (m, []) in
  function
  | Ezjsonm.Parse_error (json_value, msg) ->
      some
        ( Fmt.kstr t "JSON Parsing Error: %s, JSON:" msg
        % pre (code (t (Ezjsonm.value_to_string ~minify:false json_value))) )
  | Data_encoding.Binary.Read_error e ->
      some
        (Fmt.kstr t "Binary parsing error: %a."
           Data_encoding.Binary.pp_read_error e)
  | _ -> None

let single_error ctxt =
  let open Meta_html in
  let open Tezos_error_monad.Error_monad in
  function
  | Exn other_exn ->
      Errors_html.exception_html ctxt other_exn
        ~handlers:[json_encoding_error; simple_exns_handler]
  | Tezos_contract_metadata.Metadata_uri.Contract_metadata_uri_parsing
      parsing_error ->
      uri_parsing_error parsing_error
  | other ->
      pre
        (code
           (Fmt.kstr t "%a" Tezos_error_monad.Error_monad.pp_print_error
              [other]))

let error_trace ctxt =
  let open Meta_html in
  function
  | [] -> Bootstrap.alert ~kind:`Danger (t "Empty trace from Tezos-error-monad")
  | [h] -> single_error ctxt h
  | h :: tl ->
      single_error ctxt h
      % div
          ( t "Trace:"
          %% List.fold tl ~init:(empty ()) ~f:(fun p e ->
                 p %% single_error ctxt e) )

open Meta_html

let field_head name = Fmt.kstr (fun s -> Bootstrap.color `Info (t s)) "%s:" name
let field name content = field_head name %% content
let monot s = Bootstrap.monospace (t s)

let option_field name fieldopt f =
  match fieldopt with None -> [] | Some s -> [field name (f s)]

let normal_field name x = option_field name (Some ()) (fun () -> x)

let paragraphs blob =
  let rec go l acc =
    match List.split_while l ~f:(function "" -> false | _ -> true) with
    | ll, [] -> String.concat ~sep:" " ll :: acc
    | ll, _ :: lr -> go lr (String.concat ~sep:" " ll :: acc) in
  go (String.split blob ~on:'\n') []
  |> function
  | [] -> empty ()
  | [one] -> t one
  | more -> List.rev_map more ~f:(fun x -> div (t x)) |> H5.div

let list_field name field f =
  option_field name (match field with [] -> None | more -> Some more) f

let protocol s =
  let proto s = abbreviation s (ct (String.prefix s 12)) in
  let known name url =
    span (link ~target:url (it name)) %% t "(" % proto s % t ")" in
  match s with
  | "PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb" ->
      known "Carthage" "http://tezos.gitlab.io/protocols/006_carthage.html"
  | "PsBabyM1eUXZseaJdmXFApDSBqj8YBfwELoxZHHW77EMcAbbwAS" ->
      known "Babylon" "http://tezos.gitlab.io/protocols/005_babylon.html"
  | "PsDELPH1Kxsxt8f9eWbxQeRxkjfbxoqM52jvs5Y5fBxWWh4ifpo" ->
      known "Delphi" "https://blog.nomadic-labs.com/delphi-changelog.html"
  | s -> proto s

let open_in_editor ctxt text =
  div (small (parens (State.link_to_editor ctxt ~text (t "Open in editor"))))

let metadata_uri ?(open_in_editor_link = true) ctxt uri =
  let open Tezos_contract_metadata.Metadata_uri in
  let ct = monot in
  let rec go uri =
    match uri with
    | Web u -> t "Web URL:" %% url ct u
    | Ipfs {cid; path} ->
        let gatewayed = Fmt.str "https://gateway.ipfs.io/ipfs/%s%s" cid path in
        field_head "IPFS URI"
        % itemize
            [ field "CID" (ct cid); field "Path" (ct path)
            ; t "(Try " %% url ct gatewayed % t ")" ]
    | Storage {network; address; key} ->
        field_head "In-Contract-Storage"
        % itemize
            [ field "Network"
                (Option.value_map network
                   ~default:(t "“Current network”.")
                   ~f:ct)
            ; field "Address"
                (Option.value_map address ~default:(t "“Same contract”.")
                   ~f:Block_explorer.kt1_display)
            ; field "Key in the big-map" (Fmt.kstr ct "%S" key) ]
    | Hash {kind= `Sha256; value; target} ->
        field_head "Hash checked URI"
        % itemize
            [ field "Target" (go target)
            ; field "… should SHA256-hash to"
                (Fmt.kstr ct "%a" Hex.pp (Hex.of_string value)) ] in
  ( if open_in_editor_link then
    open_in_editor ctxt (Tezos_contract_metadata.Metadata_uri.to_string_uri uri)
  else empty () )
  % div (go uri)

let mich (Tezos_contract_metadata.Metadata_contents.Michelson_blob.Micheline m)
    =
  Michelson.micheline_canonical_to_string m

let view_result ctxt ~result ~storage ~address ~view ~parameter =
  let open Tezos_contract_metadata.Metadata_contents in
  let open View in
  let open Implementation in
  let open Michelson_storage in
  let expanded =
    try
      let retmf =
        Michelson.Partial_type.of_type ~annotations:view.human_annotations
          view.return_type in
      Michelson.Partial_type.fill_with_value retmf result ;
      match Michelson.Partial_type.render retmf with
      | [] ->
          dbgf "view_result.expanded: empty list!" ;
          bt "This should not be shown"
      | [one] -> one
      | more -> itemize more
    with exn -> Errors_html.exception_html ctxt exn in
  let mich_node = Michelson.micheline_node_to_string in
  Bootstrap.div_lead (div (bt "Result:" %% expanded))
  % hr ()
  % Bootstrap.muted div
      (let items l =
         List.fold l ~init:(empty ()) ~f:(fun p (k, v) ->
             p % div (t k % t ":" %% Bootstrap.monospace (t v))) in
       items
         [ ( "Returned Michelson"
           , Fmt.str "%s : %s" (mich_node result) (mich view.return_type) )
         ; ("Called contract", address); ("Parameter used", mich_node parameter)
         ; ("Current storage", mich_node storage) ])

let michelson_view ctxt ~view =
  let open Tezos_contract_metadata.Metadata_contents in
  let open View in
  let open Implementation in
  let open Michelson_storage in
  let {parameter; return_type; code; human_annotations; version} = view in
  let call_mode = Reactive.var false in
  let switch = Bootstrap.button ~kind:`Primary ~outline:true ~size:`Small in
  field_head "Michelson-storage-view"
  % Reactive.bind (Reactive.get call_mode) ~f:(function
      | false ->
          switch ~action:(fun () -> Reactive.set call_mode true) (t "Call")
          % itemize
              ( option_field "Michelson-Version" version protocol
              @ normal_field "Type"
                  (Fmt.kstr ct "%s<contract-storage> → %s"
                     ( match parameter with
                     | None -> ""
                     | Some p -> mich p ^ " × " )
                     (mich return_type))
              @ normal_field "Code"
                  (let concrete = mich code in
                   let lines =
                     1
                     + String.count concrete ~f:(function
                         | '\n' -> true
                         | _ -> false) in
                   if lines <= 1 then ct concrete
                   else
                     let collapse = Bootstrap.Collapse.make () in
                     Bootstrap.Collapse
                     .fixed_width_reactive_button_with_div_below collapse
                       ~width:"12em" ~kind:`Secondary
                       ~button:(function
                         | true -> t "Show Michelson"
                         | false -> t "Hide Michelson")
                       (fun () -> pre (ct concrete)))
              @ list_field "Annotations" human_annotations (fun anns ->
                    itemize
                      (List.map anns ~f:(fun (k, v) ->
                           ct k % t " → " % paragraphs v))) )
      | true ->
          let address =
            Reactive.var
              ( Contract_metadata.Uri.Fetcher.current_contract ctxt
              |> Reactive.peek |> Option.value ~default:"" ) in
          let parameter_input =
            Option.map parameter
              ~f:
                (Michelson.Partial_type.of_type
                   ~annotations:view.human_annotations) in
          let wip = Async_work.empty () in
          let go_action () =
            Async_work.wip wip ;
            let log s =
              Async_work.log wip
                (it "Calling view" %% t "→" %% Bootstrap.monospace (t s))
            in
            Async_work.async_catch wip
              ~exn_to_html:(Errors_html.exception_html ctxt)
              Lwt.Infix.(
                fun ~mkexn () ->
                  let parameter =
                    let open Michelson in
                    match parameter_input with
                    | Some mf ->
                        Michelson.Partial_type.peek mf
                        |> parse_micheline_exn ~check_indentation:false
                             ~check_primitives:false
                    | None ->
                        parse_micheline_exn ~check_indentation:false "Unit"
                          ~check_primitives:false in
                  Query_nodes.call_off_chain_view ctxt ~log
                    ~address:(Reactive.peek address) ~view ~parameter
                  >>= function
                  | Ok (result, storage) ->
                      Async_work.ok wip
                        (view_result ctxt ~result ~storage
                           ~address:(Reactive.peek address) ~view ~parameter) ;
                      Lwt.return ()
                  | Error s ->
                      Async_work.error wip (t "Error:" %% ct s) ;
                      Lwt.return ()) ;
            dbgf "go view" in
          switch ~action:(fun () -> Reactive.set call_mode false) (t "Cancel")
          % ( Async_work.is_empty wip
            |> Reactive.bind ~f:(function
                 | false -> Async_work.render wip ~f:Fn.id
                 | true ->
                     let open Bootstrap.Form in
                     let validate_address input_value =
                       match B58_hashes.check_b58_kt1_hash input_value with
                       | _ -> true
                       | exception _ -> false in
                     let input_valid =
                       Reactive.(
                         match parameter_input with
                         | Some mf -> Michelson.Partial_type.is_valid mf
                         | None -> pure true) in
                     let active =
                       Reactive.(
                         get address ** input_valid
                         |> map ~f:(fun (a, iv) -> validate_address a && iv))
                     in
                     let addr_input =
                       let addr_help a =
                         if validate_address a then
                           Bootstrap.color `Success (t "Thanks, this is valid.")
                         else
                           Bootstrap.color `Danger
                             (t "This is not a valid KT1 address") in
                       [ input
                           ~label:(t "The contract to hit the view with:")
                           ~placeholder:
                             (Reactive.pure
                                "This requires a contract address …")
                           ~help:
                             Reactive.(
                               bind
                                 ( get address
                                 ** get
                                      (Contract_metadata.Uri.Fetcher
                                       .current_contract ctxt) )
                                 ~f:(function
                                   | "", _ ->
                                       Bootstrap.color `Danger
                                         (t "Please, we need one.")
                                   | a, None -> addr_help a
                                   | a1, Some a2 ->
                                       if String.equal a1 a2 then
                                         t
                                           "This is the “main-address” \
                                            currently in context."
                                       else addr_help a1))
                           (Reactive.Bidirectional.of_var address) ] in
                     let param_input =
                       match parameter_input with
                       | None -> [magic (t "No parameter")]
                       | Some mf -> Michelson.Partial_type.to_form_items mf
                     in
                     make ~enter_action:go_action
                       ( addr_input @ param_input
                       @ [submit_button ~active (t "Go!") go_action] )) ))

let michelson_instruction s =
  link (t s) ~target:(Fmt.str "https://michelson.nomadic-labs.com/#instr-%s" s)

let metadata_validation_error ctxt =
  let open Tezos_contract_metadata.Metadata_contents in
  let open Validation.Error in
  let the_off_chain_view view = t "The off-chain-view “" % ct view % t "”" in
  function
  | Forbidden_michelson_instruction {view; instruction} ->
      the_off_chain_view view % t " uses a "
      % bt "forbidden Michelson instruction: "
      % michelson_instruction instruction
      % t " (the other forbidden instructions are: "
      % H5.span
          (oxfordize_list
             (List.filter
                ~f:String.(( <> ) instruction)
                Validation.Data.forbidden_michelson_instructions)
             ~sep:(fun () -> t ", ")
             ~last_sep:(fun () -> t ", and ")
             ~map:michelson_instruction)
      % t ")."
  | Michelson_version_not_a_protocol_hash {view; value} ->
      the_off_chain_view view
      % t " references a wrong version of Michelson ("
      % ct value
      % t "), it should be a valid protocol hash, like "
      % ct "PsDELPH1Kxsxt8f9eWbxQeRxkjfbxoqM52jvs5Y5fBxWWh4ifpo"
      % t "."

let metadata_validation_warning ctxt =
  let open Tezos_contract_metadata.Metadata_contents in
  let open Validation.Warning in
  function
  | Wrong_author_format author ->
      t "The author" %% Fmt.kstr ct "%S" author
      %% t "has a wrong format, it should look like"
      %% ct "Print Name <contact-url-or-email>"
      % t "."
  | Unexpected_whitespace {field; value} ->
      t "The field" %% ct field %% t "(=" %% Fmt.kstr ct "%S" value
      % t ") uses confusing white-space characters."
  | Self_unaddressed {view; instruction} ->
      t "The off-chain-view" %% ct view %% t "uses the instruction"
      %% michelson_instruction "SELF"
      %% ( match instruction with
         | None -> t "not followed by any instruction."
         | Some i -> t "followed by" %% michelson_instruction i % t "." )
      %% t "The current recommendation is to only use the combination"
      %% Bootstrap.monospace
           ( michelson_instruction "SELF"
           % t ";"
           %% michelson_instruction "ADDRESS" )
      %% t "in off-chain-views."

let metadata_substandards ?(add_explore_tokens_button = true) ctxt metadata =
  Contract_metadata.Content.(
    match classify metadata with
    | Tzip_16 t -> (t, [])
    | Tzip_12
        { metadata
        ; interface_claim
        ; get_balance
        ; total_supply
        ; all_tokens
        ; is_operator
        ; token_metadata
        ; permissions_descriptor } as t12 ->
        let tzip_12_block =
          let errorify c = Bootstrap.color `Danger c in
          let interface_claim =
            t "Interface claim is"
            %%
            match interface_claim with
            | None -> t "missing." |> errorify
            | Some (`Invalid s) -> t "invalid: " %% ct s |> errorify
            | Some (`Version s) -> t "valid, and defines version as" %% ct s
            | Some `Just_interface -> t "valid" in
          let view_validation ?(missing_add_on = empty) ?(mandatory = false)
              name (v : view_validation) =
            match v with
            | Missing when not mandatory ->
                t "Optional View" %% ct name %% t "is not there."
                %% missing_add_on ()
            | Missing ->
                t "Mandatory View" %% ct name %% t "is missing." |> errorify
            | No_michelson_implementation _ ->
                t "View" %% ct name
                %% t "is invalid: it is missing a Michelson implementation."
                |> errorify
            | Invalid {parameter_status; return_status; _} ->
                errorify (t "View" %% ct name %% t "is invalid:")
                %% itemize
                     [ ( t "Parameter type"
                       %%
                       match parameter_status with
                       | `Ok, _ -> t "is ok."
                       | `Wrong, None ->
                           (* This should not happen. *)
                           errorify (t "is wrong: not found.")
                       | `Wrong, Some pt ->
                           errorify
                             ( t "is wrong:"
                             %% ct
                                  (Michelson.micheline_canonical_to_string
                                     pt.original) )
                       | `Unchecked_Parameter, None ->
                           errorify (t "is expectedly not defined.")
                       | `Unchecked_Parameter, Some _ ->
                           errorify (t "is defined while it shouldn't.")
                       | `Missing_parameter, _ -> errorify (t "is missing.") )
                     ; ( t "Return type"
                       %%
                       match return_status with
                       | `Ok, _ -> t "is ok."
                       | `Wrong, None ->
                           (* This should not happen. *)
                           errorify (t "is wrong: not found.")
                       | `Wrong, Some pt ->
                           errorify
                             ( t "is wrong:"
                             %% ct
                                  (Michelson.micheline_canonical_to_string
                                     pt.original) ) ) ]
            | Valid (_, _) -> t "View" %% ct name %% t "is valid" in
          let show_permissions_descriptor pd =
            match pd with
            | None ->
                t
                  "Permissions-descriptor is not present (assuming default \
                   permissions)."
            | Some (Ok _) -> t "Permissions-descriptor is valid."
            | Some (Error e) ->
                errorify (t "Permissions-descriptor is invalid:")
                %% div (error_trace ctxt e) in
          let show_tokens_metadata tm =
            view_validation "token_metadata" tm ~missing_add_on:(fun () ->
                t
                  "This means that the contract must provide token-specific \
                   metadata using a big-map annotated with"
                %% ct "%token_metadata" % t ".") in
          let global_validity = Contract_metadata.Content.is_valid t12 in
          let show_validity_btn, validity_div =
            let validity_details () =
              itemize
                [ interface_claim
                ; view_validation "get_balance" get_balance ~mandatory:false
                ; view_validation "total_supply" total_supply
                ; view_validation "all_tokens" all_tokens
                ; view_validation "is_operator" is_operator
                ; show_tokens_metadata token_metadata
                ; show_permissions_descriptor permissions_descriptor ] in
            let open Bootstrap.Collapse in
            let collapse = make () in
            let btn =
              make_button collapse
                ~kind:(if global_validity then `Secondary else `Danger)
                (* ~style:(Reactive.pure (Fmt.str "width: 8em")) *)
                (Reactive.bind (collapsed_state collapse) ~f:(function
                  | true -> t "Expand Validity Info"
                  | false -> t "Collapse Validity Info")) in
            let dv = make_div collapse (fun () -> validity_details ()) in
            (btn, dv) in
          let wip_explore_tokens = Async_work.empty () in
          let can_enumerate_tokens, explore_tokens_btn =
            match
              (global_validity && add_explore_tokens_button, all_tokens)
            with
            | true, Valid (_, view) ->
                let action () =
                  Async_work.reinit wip_explore_tokens ;
                  Async_work.wip wip_explore_tokens ;
                  let address =
                    Reactive.var
                      ( Contract_metadata.Uri.Fetcher.current_contract ctxt
                      |> Reactive.peek
                      |> Option.value ~default:"KT1TododoTodo" ) in
                  let log s =
                    Async_work.log wip_explore_tokens
                      ( it "Exploring tokens" %% t "→"
                      %% Bootstrap.monospace (t s) ) in
                  Async_work.async_catch wip_explore_tokens
                    ~exn_to_html:(Errors_html.exception_html ctxt)
                    Lwt.Infix.(
                      fun ~mkexn () ->
                        let call_view_here view ~parameter_string =
                          let parameter =
                            let open Michelson in
                            parse_micheline_exn ~check_indentation:false
                              parameter_string ~check_primitives:false in
                          Query_nodes.call_off_chain_view ctxt ~log
                            ~address:(Reactive.peek address) ~view ~parameter
                          >>= function
                          | Ok (result, _) -> Lwt.return (Ok result)
                          | Error s -> Lwt.return (Error s) in
                        let call_view_or_fail view ~parameter_string =
                          call_view_here view ~parameter_string
                          >>= function
                          | Ok o -> Lwt.return o
                          | Error s ->
                              raise (mkexn (t "Calling view failed" %% ct s))
                        in
                        call_view_or_fail view ~parameter_string:"Unit"
                        >>= fun tokens_mich ->
                        let tokens =
                          match tokens_mich with
                          | Seq (_, nodes) ->
                              List.map nodes ~f:(function
                                | Int (_, n) -> Z.to_int n
                                | _ ->
                                    raise
                                      (mkexn
                                         ( t
                                             "Wrong Micheline structure for \
                                              result:"
                                         %% ct
                                              (Michelson
                                               .micheline_node_to_string
                                                 tokens_mich) )))
                          | _ ->
                              raise
                                (mkexn
                                   ( t "Wrong Micheline structure for result:"
                                   %% ct
                                        (Michelson.micheline_node_to_string
                                           tokens_mich) )) in
                        Fmt.kstr log "Got list of tokens %a"
                          Fmt.(Dump.list int)
                          tokens ;
                        let explore_token id =
                          let maybe_call_view view_validation ~parameter_string
                              =
                            match view_validation with
                            | Invalid _ | Missing
                             |No_michelson_implementation _ ->
                                Lwt.return_none
                            | Valid (_, view) ->
                                call_view_here view ~parameter_string
                                >>= fun res -> Lwt.return_some res in
                          maybe_call_view token_metadata
                            ~parameter_string:(Int.to_string id)
                          >>= fun metadata_map ->
                          maybe_call_view total_supply
                            ~parameter_string:(Int.to_string id)
                          >>= fun total_supply ->
                          let unpaired_metadata =
                            try
                              let nope = Decorate_error.raise in
                              let ok =
                                match metadata_map with
                                | None -> nope Message.(t "Not available")
                                | Some (Error s) ->
                                    nope
                                      Message.(t "Error getting view:" %% ct s)
                                | Some
                                    (Ok
                                      (Prim (_, "Pair", [_; Seq (l, map)], _)))
                                  -> (
                                  match map with
                                  | [] -> []
                                  | Prim
                                      ( _
                                      , "Elt"
                                      , [String (_, s); Bytes (_, b)]
                                      , _ )
                                    :: more ->
                                      List.fold more
                                        ~init:[(s, Bytes.to_string b)]
                                        ~f:(fun prev -> function
                                          | Prim
                                              ( _
                                              , "Elt"
                                              , [String (_, s); Bytes (_, b)]
                                              , _ ) ->
                                              (s, Bytes.to_string b) :: prev
                                          | other ->
                                              nope
                                                Message.(
                                                  t
                                                    "Metadata result has wrong \
                                                     structure:"
                                                  %% ct
                                                       (Michelson
                                                        .micheline_node_to_string
                                                          other)))
                                  | other ->
                                      nope
                                        Message.(
                                          t
                                            "Metadata result has wrong \
                                             structure:"
                                          %% ct
                                               (Michelson
                                                .micheline_node_to_string
                                                  (Seq (l, other)))) )
                                | Some (Ok other) ->
                                    nope
                                      Message.(
                                        t "Metadata result has wrong structure:"
                                        %% ct
                                             (Michelson.micheline_node_to_string
                                                other)) in
                              Ok ok
                            with Decorate_error.E {message} -> Error message
                          in
                          let piece_of_metadata k =
                            match unpaired_metadata with
                            | Ok s -> List.Assoc.find s k ~equal:String.equal
                            | Error _ -> None in
                          let symbol = piece_of_metadata "symbol" in
                          let name = piece_of_metadata "name" in
                          let decimals = piece_of_metadata "decimals" in
                          let extras =
                            match unpaired_metadata with
                            | Error m -> Some (Error m)
                            | Ok l -> (
                              match
                                List.filter l ~f:(fun (k, _) ->
                                    not
                                      (List.mem
                                         ["symbol"; "name"; "decimals"]
                                         k ~equal:String.equal))
                              with
                              | [] -> None
                              | m -> Some (Ok m) ) in
                          let show_extras = function
                            | Ok l ->
                                itemize
                                  (List.map l ~f:(fun (k, v) ->
                                       Fmt.kstr ct "%S" k %% t "→"
                                       %% Fmt.kstr ct "%S" v))
                            | Error m -> Message_html.render ctxt m in
                          let default_show = function
                            | Ok node ->
                                ct (Michelson.micheline_node_to_string node)
                            | Error s -> Bootstrap.color `Danger (t s) in
                          let show_total_supply = function
                            | Ok (Tezos_micheline.Micheline.Int (_, z)) -> (
                              match Option.map ~f:Int.of_string decimals with
                              | Some decimals ->
                                  let dec =
                                    Float.(
                                      Z.to_float z / (10. ** of_int decimals))
                                  in
                                  Fmt.kstr t "%s (%a Units)"
                                    (Float.to_string_hum ~delimiter:' '
                                       ~decimals ~strip_zero:true dec)
                                    Z.pp_print z
                              | None | (exception _) ->
                                  Fmt.kstr t "%a Units (no decimals)"
                                    Z.pp_print z )
                            | other -> ct "Error: " %% default_show other in
                          let metarows =
                            let or_not n o ~f =
                              match o with
                              | None -> [(n, empty ())]
                              | Some s -> [(n, f s)] in
                            [("Token Id", Fmt.kstr ct "%04d" id)]
                            @ or_not "Total Supply" total_supply
                                ~f:show_total_supply
                            @ or_not "Symbol" symbol ~f:it
                            @ or_not "Name" name ~f:it
                            @ or_not "Decimals" decimals ~f:it
                            @ or_not "“Extras”" extras ~f:show_extras
                            (* @ or_not "Full-Metadata" metadata_map
                                ~f:default_show *) in
                          Lwt.return metarows in
                        Lwt_list.map_s explore_token tokens
                        >>= fun decorated_tokens ->
                        let token_list =
                          match decorated_tokens with
                          | [] -> bt "There are no tokens :("
                          | one :: more ->
                              let fields = List.map one ~f:fst in
                              let header_row = List.map fields ~f:t in
                              Bootstrap.Table.simple ~header_row
                                (List.fold (one :: more) ~init:(empty ())
                                   ~f:(fun prev tok ->
                                     prev
                                     % H5.tr
                                         (List.map tok ~f:(fun (_, v) -> td v))))
                        in
                        Async_work.ok wip_explore_tokens token_list ;
                        Lwt.return ()) ;
                  dbgf "go view" in
                ( true
                , Bootstrap.button ~kind:`Primary ~size:`Small ~outline:true
                    ~action (t "Explore Tokens") )
            | _ -> (false, empty ()) in
          let tokens_exploration x = div (bt "Tokens:" % div x) in
          div
            ( t "This looks like a TZIP-12 contract (a.k.a. FA2);"
            %%
            match global_validity with
            | true ->
                Bootstrap.color `Success (t "it seems valid")
                %%
                if can_enumerate_tokens then
                  parens (t "and tokens can be enumerated/explored") % t "."
                else t "."
            | false -> Bootstrap.color `Danger (t "it is invalid.") )
          % div
              ( show_validity_btn % explore_tokens_btn % validity_div
              % Async_work.render wip_explore_tokens ~f:tokens_exploration )
        in
        (metadata, [field "TZIP-12 Implementation Claim" tzip_12_block]))

let metadata_contents ~add_explore_tokens_button ?(open_in_editor_link = true)
    ctxt =
  let open Tezos_contract_metadata.Metadata_contents in
  fun (*  as *) metadata ->
    let ct = monot in
    let license_elt l =
      let open License in
      it l.name
      % Option.value_map ~default:(empty ()) l.details ~f:(fun d ->
            Fmt.kstr t " → %s" d) in
    let url_elt u = url ct u in
    let authors_elt l =
      let author s =
        try
          match String.split (String.strip s) ~on:'<' with
          | [name; id] -> (
            match String.lsplit2 id ~on:'>' with
            | Some (u, "") when String.is_prefix u ~prefix:"http" ->
                t name %% parens (url_elt u)
            | Some (u, "")
            (* we won't get into email address regexps here, sorry *)
              when String.mem u '@' ->
                t name %% parens (link ~target:("mailto:" ^ u) (ct u))
            | _ -> failwith "" )
          | _ -> failwith ""
        with _ -> ct s in
      oxfordize_list l ~map:author
        ~sep:(fun () -> t ", ")
        ~last_sep:(fun () -> t ", and ")
      |> list in
    let interfaces_elt l =
      let interface s =
        let r = Re.Posix.re "TZIP-([0-9]+)" in
        let normal s = it s in
        let tok = function
          | `Text s -> normal s
          | `Delim g -> (
              let the_text = normal (Re.Group.get g 0) in
              try
                let tzip_nb = Re.Group.get g 1 |> Int.of_string in
                link the_text
                  ~target:
                    (Fmt.str
                       "https://gitlab.com/tzip/tzip/-/blob/master/proposals/tzip-%d/tzip-%d.md"
                       tzip_nb tzip_nb)
                (* Fmt.kstr txt "{%a --- %d}" Re.Group.pp g (Re.Group.nb_groups g)] *)
              with e ->
                dbgf "Error in interface html: %a" Exn.pp e ;
                the_text ) in
        Re.split_full (Re.compile r) s |> List.map ~f:tok |> list in
      List.map l ~f:interface |> List.intersperse ~sep:(t ", ") |> list in
    let _todo l = Fmt.kstr t "todo: %d items" (List.length l) in
    let view_id s = Fmt.str "view-%s" s in
    let view ?(collapsing = false) v =
      let open View in
      let purity =
        if v.is_pure then Bootstrap.color `Success (t "pure")
        else Bootstrap.color `Warning (t "impure") in
      let implementations impls =
        let open Implementation in
        itemize
          (List.map impls ~f:(function
            | Michelson_storage view -> michelson_view ctxt ~view
            | Rest_api_query raq ->
                field "REST-API Query"
                  (itemize
                     ( normal_field "OpenAPI Spec" (ct raq.specification_uri)
                     @ option_field "Base-URI Override" raq.base_uri ct
                     @ normal_field "Path" (ct raq.path)
                     @ normal_field "Method"
                         (Fmt.kstr ct "%s"
                            (Cohttp.Code.string_of_method raq.meth)) )))) in
      let maybe_collapse content =
        if collapsing then
          let open Bootstrap.Collapse in
          let collapse = make () in
          let btn =
            make_button collapse ~kind:`Secondary
              ~style:(Reactive.pure (Fmt.str "width: 8em"))
              (Reactive.bind (collapsed_state collapse) ~f:(function
                | true -> t "Expand"
                | false -> t "Collapse")) in
          let dv = make_div collapse (fun () -> content) in
          btn %% dv
        else content in
      div
        ~a:[H5.a_id (Lwd.pure (view_id v.name))]
        ( bt v.name %% t "(" % purity % t "):"
        % maybe_collapse
            (itemize
               ( option_field "Description" v.description paragraphs
               @
               match v.implementations with
               | [] ->
                   [Bootstrap.color `Danger (t "There are no implementations.")]
               | l ->
                   let name =
                     Fmt.str "Implementation%s"
                       (if List.length l = 1 then "" else "s") in
                   list_field name v.implementations implementations )) ) in
    let views_elt (views : View.t list) =
      let collapsing = List.length views >= 3 in
      itemize (List.map views ~f:(fun v -> view ~collapsing v)) in
    let source_elt source =
      let open Source in
      let tool s =
        let links =
          [ ("michelson", "https://tezos.gitlab.io")
          ; ("smartpy", "https://smartpy.io")
          ; ("flextesa", "https://tezos.gitlab.io/flextesa")
          ; ("dune", "https://dune.build")
          ; ("archetype", "https://archetype-lang.org/")
          ; ("ligo", "https://ligolang.org/")
          ; ("cameligo", "https://ligolang.org/")
          ; ("pascaligo", "https://ligolang.org/")
          ; ("reasonligo", "https://ligolang.org/")
          ; ("morley", "https://gitlab.com/morley-framework/morley")
          ; ("lorentz", "https://serokell.io/project-lorentz-indigo")
          ; ("indigo", "https://serokell.io/project-lorentz-indigo")
          ; ("scaml", "https://www.scamlang.dev/") ] in
        let splitted = String.split ~on:' ' s in
        match splitted with
        | [] | [""] -> t "Empty Tool 👎"
        | one :: more ->
            let uncap = String.lowercase one in
            List.find_map links ~f:(fun (prefix, target) ->
                if String.equal uncap prefix then
                  Some
                    ( link ~target (bt one)
                    %
                    match more with
                    | [] -> empty ()
                    | _ -> t " " % parens (ct (String.concat ~sep:" " more)) )
                else None)
            |> Option.value ~default:(bt s) in
      itemize
        ( field "Tools"
            ( ( oxfordize_list source.tools ~map:tool
                  ~sep:(fun () -> t ", ")
                  ~last_sep:(fun () -> t ", and ")
              |> list )
            % t "." )
        :: option_field "Location" source.location url_elt ) in
    let errors_elt ~views errors =
      let open Errors.Translation in
      let langs = function
        | None -> empty ()
        | Some [] -> div (t "[lang=?]")
        | Some more ->
            div
              ( t "[lang="
              % list
                  (let sep () = t "|" in
                   oxfordize_list more ~map:ct ~sep ~last_sep:sep)
              % t "]" ) in
      let expand (Michelson_blob.Micheline m as mm) =
        let open Tezos_micheline.Micheline in
        let qit s =
          abbreviation
            (Fmt.str "Michelson: %s" (mich mm))
            (Fmt.kstr it "“%s”" s) in
        match root m with
        | String (_, s) -> qit s
        | Bytes (_, b) -> qit (Bytes.to_string b)
        | _ -> ct (mich mm) in
      let view_link name =
        List.find views ~f:(fun v -> String.equal name v.View.name)
        |> function
        | None ->
            ct name %% small (Bootstrap.color `Danger (t "(Cannot find it!)"))
        | Some v ->
            let collapse = Bootstrap.Collapse.make () in
            Bootstrap.Collapse.make_button ~kind:`Secondary collapse (ct name)
            % Bootstrap.Collapse.make_div collapse (fun () -> view v) in
      itemize
        (List.map errors ~f:(function
          | Static {error; expansion; languages} ->
              field "Static-translation"
                ( ct (mich error)
                %% t "→" %% expand expansion %% langs languages )
          | Dynamic {view_name; languages} ->
              field "Dynamic-view" (view_link view_name %% langs languages)))
    in
    let unknown_extras kv =
      itemize
        (List.map kv ~f:(fun (k, v) ->
             ct k %% pre (ct (Ezjsonm.value_to_string ~minify:false v)))) in
    let ( { name
          ; description
          ; version
          ; license
          ; authors
          ; homepage
          ; source
          ; interfaces
          ; errors
          ; views
          ; unknown }
        , sub_standards ) =
      metadata_substandards ~add_explore_tokens_button ctxt metadata in
    ( if open_in_editor_link then
      open_in_editor ctxt
        (Tezos_contract_metadata.Metadata_contents.to_json metadata)
    else empty () )
    % itemize
        ( option_field "Name" name ct
        @ option_field "Version" version ct
        @ option_field "Description" description paragraphs
        @ list_field "Interfaces" interfaces interfaces_elt
        @ sub_standards
        @ option_field "License" license license_elt
        @ option_field "Homepage" homepage url_elt
        @ option_field "Source" source source_elt
        @ list_field "Authors" authors authors_elt
        @ option_field "Errors" errors (errors_elt ~views)
        @ list_field "Views" views views_elt
        @ list_field "Extra/Unknown" unknown unknown_extras )