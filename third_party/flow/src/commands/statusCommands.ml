(**
 * Copyright (c) 2014, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "flow" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

open CommandInfo

(***********************************************************************)
(* flow status (report current error set) command impl *)
(***********************************************************************)

module type CONFIG = sig
  (* explicit == called with "flow status ..."
     rather than simply "flow ..." *)
  val explicit : bool
end

module Impl (CommandList : COMMAND_LIST) (Config : CONFIG) = struct

  let spec = if Config.explicit
  then
    {
      CommandSpec.
      name = "status";
      doc = "(default) Shows current Flow errors by asking the Flow server";
      usage = Printf.sprintf
        "Usage: %s status [OPTION]... [ROOT]\n\
          Shows current Flow errors by asking the Flow server.\n\n\
          Flow will search upward for a .flowconfig file, beginning at ROOT.\n\
          ROOT is assumed to be the current directory if unspecified.\n\
          A server will be started if none is running over ROOT.\n\
          \n\
          Status command options:"
          CommandUtils.exe_name;
      args = CommandSpec.ArgSpec.(
        empty
        |> CommandUtils.server_flags
        |> CommandUtils.json_flags
        |> CommandUtils.error_flags
        |> dummy false (* match --version below *)
        |> anon "root" (optional string) ~doc:"Root directory"
      )
    }
  else
    let command_info = CommandList.commands
      |> List.map (fun (command) ->
        (CommandSpec.name command, CommandSpec.doc command)
      )
      |> List.filter (fun (cmd, doc) -> cmd <> "" && doc <> "")
      |> List.sort (fun (a, _) (b, _) -> String.compare a b)
    in
    let col_width = List.fold_left
      (fun acc (cmd, _) -> max acc (String.length cmd)) 0 command_info in
    let cmd_usage = command_info
      |> List.map (fun (cmd, doc) ->
            Utils.spf "  %-*s  %s" col_width cmd doc
         )
      |> String.concat "\n"
    in
    {
      CommandSpec.
      name = "default";
      doc = "";
      usage = Printf.sprintf
        "Usage: %s [COMMAND] \n\n\
          Valid values for COMMAND:\n%s\n\n\
          Default values if unspecified:\n\
            \ \ COMMAND\
              \tstatus\n\
          \n\
          Status command options:"
          CommandUtils.exe_name
          cmd_usage;
      args = CommandSpec.ArgSpec.(
        empty
        |> CommandUtils.server_flags
        |> CommandUtils.json_flags
        |> CommandUtils.error_flags
        |> flag "--version" no_arg
            ~doc:"Print version number and exit"
        |> anon "root" (optional string) ~doc:"Root directory"
      )
    }

  type env = {
    root: Path.t;
    from: string;
    output_json: bool;
    one_line: bool;
    color: Tty.color_mode;
    show_all_errors: bool;
  }

  let rec check_status (args:env) option_values =
    let name = "flow" in

    let ic, oc = CommandUtils.connect_with_autostart option_values args.root in
    ServerProt.cmd_to_channel oc (ServerProt.STATUS args.root);
    let response = ServerProt.response_from_channel ic in
    match response with
    | ServerProt.DIRECTORY_MISMATCH d ->
      Printf.printf "%s is running on a different directory.\n" name;
      Printf.printf "server_root: %s, client_root: %s\n"
        (Path.to_string d.ServerProt.server)
        (Path.to_string d.ServerProt.client);
      flush stdout;
      raise CommandExceptions.Server_directory_mismatch
    | ServerProt.ERRORS e ->
      if args.output_json || args.from <> ""
      then Errors_js.print_errorl args.output_json e stdout
      else (
        Errors_js.print_error_summary
          ~one_line:args.one_line
          ~color:args.color
          (not args.show_all_errors) e
      );
      exit 2
    | ServerProt.NO_ERRORS ->
      Errors_js.print_errorl args.output_json [] stdout;
      exit 0
    | ServerProt.PONG ->
        Printf.printf "Why on earth did the server respond with a pong?\n%!";
        exit 2
    | ServerProt.SERVER_DYING ->
      Printf.printf "Server has been killed for %s\n"
        (Path.to_string args.root);
      exit 2
    | ServerProt.SERVER_OUT_OF_DATE ->
      if option_values.CommandUtils.no_auto_start
      then Printf.printf "%s is outdated, killing it.\n" name
      else Printf.printf "%s is outdated, going to launch a new one.\n" name;
      flush stdout;
      retry (args, option_values) 3 "The flow server will be ready in a moment"

  and retry (env, option_values) sleep msg =
    CommandUtils.check_timeout ();
    let retries = option_values.CommandUtils.retries in
    if retries > 0
    then begin
      Printf.fprintf stderr "%s\n%!" msg;
      CommandUtils.sleep sleep;
      check_status env { option_values with CommandUtils.retries = retries - 1 }
    end else begin
      Printf.fprintf stderr "Out of retries, exiting!\n%!";
      exit 2
    end

  let main option_values json color one_line show_all_errors version root () =
    if version then (
      CommandUtils.print_version ();
      exit 0
    );

    let root = CommandUtils.guess_root root in
    let timeout_arg = option_values.CommandUtils.timeout in
    if timeout_arg > 0 then CommandUtils.set_timeout timeout_arg;
    let env = {
      color = CommandUtils.parse_color_enum color;
      root;
      from = option_values.CommandUtils.from;
      output_json = json;
      one_line;
      show_all_errors;
    } in
    check_status env option_values
end

module Status(CommandList : COMMAND_LIST) = struct
  module Main = Impl (CommandList) (struct let explicit = true end)
  let command = CommandSpec.command
    Main.spec
    (CommandUtils.collect_server_flags Main.main)
end

module Default(CommandList : COMMAND_LIST) = struct
  module Main = Impl (CommandList) (struct let explicit = false end)
  let command = CommandSpec.command
    Main.spec
    (CommandUtils.collect_server_flags Main.main)
end
