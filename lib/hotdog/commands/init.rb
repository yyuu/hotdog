#!/usr/bin/env ruby

module Hotdog
  module Commands
    class Init < BaseCommand
      def run(args=[])
        execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS hosts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255) NOT NULL
          );
        EOS
        execute(<<-EOS)
          CREATE UNIQUE INDEX IF NOT EXISTS hosts_name ON hosts ( name );
        EOS
        execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(200) NOT NULL,
            value VARCHAR(200) NOT NULL DEFAULT ""
          );
        EOS
        execute(<<-EOS)
          CREATE UNIQUE INDEX IF NOT EXISTS tags_name_value ON tags ( name, value );
        EOS
        execute(<<-EOS)
          CREATE TABLE IF NOT EXISTS hosts_tags (
            host_id INTEGER NOT NULL,
            tag_id INTEGER NOT NULL
          );
        EOS
        execute(<<-EOS)
          CREATE UNIQUE INDEX IF NOT EXISTS hosts_tags_host_id_tag_id ON hosts_tags ( host_id, tag_id );
        EOS

        application.run_command("update")
      end
    end
  end
end

# vim:set ft=ruby :
