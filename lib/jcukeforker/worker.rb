require 'socket'
require 'securerandom'
require 'json'

status_path = $ARGV[0]
task_path = $ARGV[1]

module JCukeForker
  class Worker

    attr_reader :feature, :format, :out

    def initialize(status_path, task_path)
      @status_path = status_path
      @task_path = task_path
      @status_socket = TCPSocket.new 'localhost', status_path
    end

    def register
      @worker_server = UNIXServer.new @task_path
      update_status :on_worker_register
    end

    def close
      @worker_server.close
      @status_socket.close
    end

    def run
      worker_socket = @worker_server.accept
      loop do
        raw_message = worker_socket.gets
        if raw_message.strip == '__KILL__'
          update_status :on_worker_dead
          break
        end
        set_state raw_message
        update_status :on_task_starting, feature
        status = execute_cucumber raw_message
        update_status :on_task_finished, feature, status
      end
    end

    def update_status(meth, *args)
      message = [meth, @task_path]
      message += args

      @status_socket.puts(message.to_json)
    end

    def output
      File.join out, "#{basename}.#{format}"
    end

    def stdout
      File.join out, "#{basename}.stdout"
    end

    def stderr
      File.join out, "#{basename}.stderr"
    end

    def basename
      @basename ||= feature.gsub(/\W/, '_')
    end

    def args
      args = %W[--format #{format} --out #{output}]
      args += @extra_args
      args << feature

      args
    end

    def set_state(raw_message)
      json_obj = JSON.parse raw_message
      @format = json_obj['format']
      @feature = json_obj['feature']
      @extra_args = json_obj['extra_args']
      @out = json_obj['out']
    end

    def execute_cucumber
      FileUtils.mkdir_p(out) unless File.exist? out

      $stdout.reopen stdout
      $stderr.reopen stderr

      failed = Cucumber::Cli::Main.execute args

      $stdout.flush
      $stderr.flush

      failed
    end
  end
end

worker = JCukeForker::Worker.new status_path, task_path
worker.register
worker.run
worker.close