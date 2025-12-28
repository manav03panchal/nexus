defmodule Nexus.Property.DSLParserTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Nexus.DSL.{Parser, Validator}
  alias Nexus.Types.Host

  @moduletag :property

  describe "Host.parse/2" do
    property "any valid hostname string parses successfully" do
      check all(
              hostname <- hostname_generator(),
              user <- one_of([constant(nil), username_generator()]),
              port <- one_of([constant(22), integer(1..65_535)])
            ) do
        host_string = build_host_string(hostname, user, port)
        assert {:ok, host} = Host.parse(:test_host, host_string)
        assert host.hostname == hostname

        if user do
          assert host.user == user
        end

        assert host.port == port
      end
    end

    property "parsed host can be reconstructed to equivalent string" do
      check all(
              hostname <- hostname_generator(),
              user <- username_generator(),
              port <- integer(1..65_535)
            ) do
        host_string = "#{user}@#{hostname}:#{port}"
        assert {:ok, host} = Host.parse(:test, host_string)

        reconstructed = "#{host.user}@#{host.hostname}:#{host.port}"
        assert reconstructed == host_string
      end
    end

    property "hostname-only strings default to port 22" do
      check all(hostname <- hostname_generator()) do
        assert {:ok, host} = Host.parse(:test, hostname)
        assert host.port == 22
        assert host.user == nil
      end
    end
  end

  describe "Parser.parse_string/1" do
    property "any valid task name atom can be used" do
      check all(task_name <- task_name_generator()) do
        dsl = """
        task :#{task_name} do
          run "echo test"
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert Map.has_key?(config.tasks, task_name)
      end
    end

    property "multiple hosts can be defined" do
      check all(host_count <- integer(1..10)) do
        host_defs =
          Enum.map_join(1..host_count, "\n", fn i ->
            "host :host#{i}, \"host#{i}.example.com\""
          end)

        assert {:ok, config} = Parser.parse_string(host_defs)
        assert map_size(config.hosts) == host_count
      end
    end

    property "multiple tasks can be defined" do
      check all(task_count <- integer(1..10)) do
        task_defs =
          Enum.map_join(1..task_count, "\n", fn i ->
            """
            task :task#{i} do
              run "echo task #{i}"
            end
            """
          end)

        assert {:ok, config} = Parser.parse_string(task_defs)
        assert map_size(config.tasks) == task_count
      end
    end

    property "task with multiple commands preserves order" do
      check all(cmd_count <- integer(1..20)) do
        cmds =
          Enum.map_join(1..cmd_count, "\n", fn i ->
            "  run \"command #{i}\""
          end)

        dsl = """
        task :test do
        #{cmds}
        end
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        commands = config.tasks[:test].commands

        assert length(commands) == cmd_count

        commands
        |> Enum.with_index(1)
        |> Enum.each(fn {cmd, i} ->
          assert cmd.cmd == "command #{i}"
        end)
      end
    end

    property "config values are preserved" do
      check all(
              timeout <- integer(1000..100_000),
              max_conn <- integer(1..100)
            ) do
        dsl = """
        config :nexus,
          connect_timeout: #{timeout},
          max_connections: #{max_conn}
        """

        assert {:ok, config} = Parser.parse_string(dsl)
        assert config.connect_timeout == timeout
        assert config.max_connections == max_conn
      end
    end
  end

  describe "Validator" do
    property "validation is deterministic" do
      check all(
              host_count <- integer(0..5),
              task_count <- integer(0..5)
            ) do
        host_defs =
          Enum.map_join(1..max(host_count, 1), "\n", fn i ->
            "host :host#{i}, \"host#{i}.example.com\""
          end)

        task_defs =
          if task_count > 0 do
            Enum.map_join(1..task_count, "\n", fn i ->
              """
              task :task#{i} do
                run "echo #{i}"
              end
              """
            end)
          else
            ""
          end

        dsl = host_defs <> "\n" <> task_defs
        {:ok, config} = Parser.parse_string(dsl)

        # Validate multiple times and ensure consistent results
        result1 = Validator.validate(config)
        result2 = Validator.validate(config)
        result3 = Validator.validate(config)

        assert result1 == result2
        assert result2 == result3
      end
    end
  end

  # Generators

  defp hostname_generator do
    gen all(segments <- list_of(segment_generator(), min_length: 1, max_length: 4)) do
      Enum.join(segments, ".")
    end
  end

  defp segment_generator do
    gen all(
          chars <-
            list_of(one_of([integer(?a..?z), integer(?0..?9)]), min_length: 1, max_length: 10)
        ) do
      to_string(chars)
    end
  end

  defp username_generator do
    gen all(
          chars <-
            list_of(one_of([integer(?a..?z), integer(?0..?9), constant(?_)]),
              min_length: 1,
              max_length: 16
            )
        ) do
      to_string(chars)
    end
  end

  defp task_name_generator do
    gen all(
          first <- integer(?a..?z),
          rest <-
            list_of(one_of([integer(?a..?z), integer(?0..?9), constant(?_)]), max_length: 15)
        ) do
      String.to_atom(to_string([first | rest]))
    end
  end

  defp build_host_string(hostname, nil, 22), do: hostname
  defp build_host_string(hostname, nil, port), do: "#{hostname}:#{port}"
  defp build_host_string(hostname, user, 22), do: "#{user}@#{hostname}"
  defp build_host_string(hostname, user, port), do: "#{user}@#{hostname}:#{port}"
end
