require File.dirname(__FILE__) + '/../test_helper'

class BuildTest < ActiveSupport::TestCase
  include FileSandbox

  def test_build_should_know_if_it_is_the_latest
    with_sandbox_project do |sandbox, project|
      sandbox.new :directory => "build-2"
      build_old = Build.new(project, 2)

      sandbox.new :directory => "build-3"
      build_latest = Build.new(project, 3)

      assert build_latest.latest?
      assert_false build_old.latest?
    end
  end
  
  def test_should_be_able_to_fail_a_build
    with_sandbox_project do |sandbox, project|
      sandbox.new :directory => "build-1"
      now = Time.now
      Time.stubs(:now).returns(now)
      
      build = Build.new(project, 1)
      
      now += 10.seconds
      Time.stubs(:now).returns(now)
      build.expects(:remove_pid_file!)
      build.fail!("I tripped")
      
      assert_equal true, build.failed?
      assert_equal "I tripped", build.error
    end
  end
  
  def test_dont_complain_if_there_is_no_error
    with_sandbox_project do |sandbox, project|
      sandbox.new :directory => "build-1"
      Build.new(project, 1).brief_error
    end
  end

  def test_initialize_should_load_status_file_and_build_log
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-2-success.in9.235s/build.log", :with_content => "some content"
      build = Build.new(project, 2)
  
      assert_equal '2', build.label
      assert_equal true, build.successful?
      assert_equal "some content", build.output
    end
  end

  def test_initialize_should_load_failed_status_file
    with_sandbox_project do |sandbox, project|
      sandbox.new :directory => "build-2-failed.in2s"
      build = Build.new(project, 2)
  
      assert_equal '2', build.label
      assert_equal true, build.failed?
    end
  end

  def test_output_grabs_log_file_when_file_exists
    with_sandbox_project do |sandbox, project|
      build_log = "#{project.path}/build-1/build.log"
      File.expects(:file?).with(build_log).returns(true)
      File.expects(:readable?).with(build_log).returns(true)
      File.expects(:size).with(build_log).returns(14)
      File.expects(:read).with(build_log).returns(['line 1', 'line 2'])
      assert_equal ['line 1', 'line 2'], Build.new(project, 1).output
    end
  end


  def test_artifacts_directory_method_should_remove_cached_pages
    with_sandbox_project do |sandbox, project|
      project = create_project_stub('one', 'success')
      FileUtils.expects(:rm_f).with("#{RAILS_ROOT}/public/builds/older/#{project.name}.html")
      Build.new(project, 1, true)
    end
  end
  
  def test_output_gives_empty_string_when_file_does_not_exist
    with_sandbox_project do |sandbox, project|
      File.expects(:file?).with("#{project.path}/build-1/build.log").returns(true)
      assert_equal "", Build.new(project, 1).output
    end
  end
  
  def test_pid_returns_int_when_pid_file_exists
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-2-success.in9.235s/build.pid", :with_content => "16568"
      build = Build.new(project, 2)
      assert_equal 16568, build.pid
    end
  end

  def test_pid_returns_zero_when_file_does_not_exist
    with_sandbox_project do |sandbox,project|
      assert_equal 0, Build.new(project, 1).pid
    end
  end

  def test_terminate_should_kill_process_when_build_is_incomplete
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-123/build.pid", :with_content => "16568"
      build = Build.new(project, 123)
      Process.expects(:kill).with("SIGTERM", build.pid)
      build.terminate
    end
  end

  def test_terminate_should_not_kill_process_when_build_is_failed
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-123-failed.in2s/build.pid", :with_content => "16568"
      build = Build.new(project, 123)
      Process.expects(:kill).never
      build.terminate
    end
  end

  def test_terminate_should_not_kill_process_when_build_is_failed
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-123-success.in2s/build.pid", :with_content => "16568"
      build = Build.new(project, 123)
      Process.expects(:kill).never
      build.terminate
    end
  end

  def test_successful?
    with_sandbox_project do |sandbox, project|
      sandbox.new :directory => "build-1-success"
      sandbox.new :directory => "build-2-Success"
      sandbox.new :directory => "build-3-failure"
      sandbox.new :directory => "build-4-crap"
      sandbox.new :directory => "build-5"

      assert Build.new(project, 1).successful?
      assert Build.new(project, 2).successful?
      assert !Build.new(project, 3).successful?
      assert !Build.new(project, 4).successful?
      assert !Build.new(project, 5).successful?
    end
  end

  def test_incomplete?
    with_sandbox_project do |sandbox, project|
      sandbox.new :directory => "build-1-incomplete"
      sandbox.new :directory => "build-2-something_else"
  
      assert Build.new(project, 1).incomplete?
      assert !Build.new(project, 2).incomplete?
    end
  end

  def test_run_successful_build
    with_sandbox_project do |sandbox, project|
      expected_build_directory = File.join(sandbox.root, 'build-123')
  
      Time.expects(:now).at_least(2).returns(Time.at(0), Time.at(3.2))
      build = Build.new(project, 123, true)
  
      expected_build_log = File.join(expected_build_directory, 'build.log')
      expected_pid_file  = File.join(expected_build_directory, 'build.pid')
      expected_redirect_options = {
          :stdout => expected_build_log,
          :stderr => expected_build_log,
          :pid_file => expected_pid_file
        }
      build.expects(:execute).with(build.rake, expected_redirect_options).returns("hi, mom!")
      build.expects(:remove_pid_file!)

      BuildStatus.any_instance.expects(:'succeed!').with(4)
      BuildStatus.any_instance.expects(:'fail!').never
      build.run
    end
  end

  def test_run_stores_settings
    with_sandbox_project do |sandbox, project|
      project.stubs(:config_file_content).returns("cool project settings")
  
      build = Build.new(project, 123, true)
      build.stubs(:execute)

      build.run
      assert_equal 'cool project settings', SandboxFile.new(Dir['build-123-success.in*s/cruise_config.rb'][0]).contents
      assert_equal 'cool project settings', Build.new(project, 123).project_settings
    end
  end

  def test_run_unsuccessful_build
    with_sandbox_project do |sandbox, project|
      expected_build_directory = File.join(sandbox.root, 'build-123')
  
      Time.stubs(:now).returns(Time.at(1))
      build = Build.new(project, 123, true)
  
      expected_build_log = File.join(expected_build_directory, 'build.log')
      expected_pid_file  = File.join(expected_build_directory, 'build.pid')
      expected_redirect_options = {
        :stdout => expected_build_log,
        :stderr => expected_build_log,
        :pid_file => expected_pid_file
      }

      error = RuntimeError.new("hello")
      build.expects(:execute).with(build.rake, expected_redirect_options).raises(error)
      BuildStatus.any_instance.expects(:'fail!').with(0, "hello")  
      build.run
    end
  end

  def test_warn_on_mistake_check_out_if_trunk_dir_exists
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "work/trunk/rakefile"
    
      expected_build_directory = File.join(sandbox.root, 'build-123')
  
      build = Build.new(project, 123, true)

      expected_build_log = File.join(expected_build_directory, 'build.log')
      expected_pid_file  = File.join(expected_build_directory, 'build.pid')
      expected_redirect_options = {
        :stdout => expected_build_log,
        :stderr => expected_build_log,
        :pid_file => expected_pid_file
      }
  
      build.expects(:execute).with(build.rake, expected_redirect_options).raises(CommandLine::ExecutionError)
      build.run
      
      log = SandboxFile.new(Dir["build-123-failed.in*s/build.log"].first).content
      assert_match /trunk exists/, log
    end
  end
  
  def test_brief_error_is_short_with_execution_error
    with_sandbox_project do |sandbox, project|
      build = Build.new(project, 123, true)

      build.expects(:execute).raises(CommandLine::ExecutionError.new(*%w(a b c d e)))
      build.run
      
      assert_equal "", build.error
    end
  end
  
  def test_status
    with_sandbox_project do |sandbox, project|
      BuildStatus.any_instance.expects(:to_s)
      Build.new(project, 123).status
    end
  end
  
  def test_build_command_customization
    with_sandbox_project do |sandbox, project|
      build_with_defaults = Build.new(project, '1')
      assert_match(/cc_build.rake'; ARGV << '--nosearch' << 'cc:build'/, build_with_defaults.command)
      assert_nil build_with_defaults.rake_task
  
      project.rake_task = 'my_build_task'
      build_with_custom_rake_task = Build.new(project, '2')
      assert_match(/cc_build.rake'; ARGV << '--nosearch' << 'cc:build'/, build_with_custom_rake_task.command)
      assert_equal 'my_build_task', build_with_custom_rake_task.rake_task
  
      project.rake_task = nil
      project.build_command = 'my_build_script.sh'
      build_with_custom_script = Build.new(project, '3')
      assert_equal 'my_build_script.sh', build_with_custom_script.command
      assert_nil build_with_custom_script.rake_task
    end
  end
  
  def test_build_should_know_about_additional_artifacts
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-1/coverage/index.html"
      sandbox.new :file => "build-1/coverage/units/index.html"
      sandbox.new :file => "build-1/coverage/functionals/index.html"
      sandbox.new :file => "build-1/foo"
      sandbox.new :file => "build-1/foo.txt"
      sandbox.new :file => "build-1/cruise_config.rb"
      sandbox.new :file => "build-1/plugin_errors.log"
      sandbox.new :file => "build.log"
      sandbox.new :file => "build_status.failure"
      sandbox.new :file => "changeset.log"

      build = Build.new(project, 1)
      assert_equal(%w(coverage foo foo.txt), build.additional_artifacts.sort)
    end
  end

  def test_build_should_fail_if_project_config_is_invalid
    Time.stubs(:now).returns(Time.at(0))
    with_sandbox_project do |sandbox, project|
      project.stubs(:config_file_content).returns("cool project settings")
      project.stubs(:error_message).returns("some project config error")
      project.expects(:'config_valid?').returns(false)
      build = Build.new(project, 123, true)
      build.run
      assert build.failed?
      log_message = File.open("build-123-failed.in0s/build.log"){|f| f.read }
      assert_equal "some project config error", log_message
    end
  end

  def test_should_pass_error_to_build_status_if_config_file_is_invalid
    Time.stubs(:now).returns(Time.at(0))
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-1/build.log"
      project.stubs(:error_message).returns("fail message")
      project.stubs(:"config_valid?").returns(false)
      
      build = Build.new(project, 1, true)
      build.run
      assert_equal "fail message", File.open("build-1-failed.in0s/error.log"){|f|f.read}
      assert_equal "fail message", build.brief_error
    end   
  end
    
  def test_should_pass_error_to_build_status_if_plugin_error_happens
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-1-success.in0s/error.log"
      build = Build.new(project, 1)
      build.stubs(:plugin_errors).returns("plugin error")
      assert_equal "plugin error", build.brief_error
    end   
  end    
  
  def test_should_generate_build_url_with_dashboard_url
    with_sandbox_project do |sandbox, project|
      sandbox.new :file => "build-1/build_status.success.in0s"
      build = Build.new(project, 1)

      dashboard_url = "http://www.my.com"
      Configuration.expects(:dashboard_url).returns(dashboard_url)      
      assert_equal "#{dashboard_url}/builds/#{project.name}/#{build.to_param}", build.url
      
      Configuration.expects(:dashboard_url).returns(nil)
      assert_raise(RuntimeError) { build.url }
    end
  end
  
  def test_in_clean_environment_on_local_copy_should_not_pass_current_rails_env_to_block
    ENV['RAILS_ENV'] = 'craziness'
    with_sandbox_project do |sandbox, project|
      build = Build.new(project, 1)
    
      build.in_clean_environment_on_local_copy do
        assert_equal nil, ENV['RAILS_ENV']
      end
      
      assert_equal 'craziness', ENV['RAILS_ENV']
    end    
  ensure
    ENV['RAILS_ENV'] = 'test'
  end

  def test_abbreviated_label
    with_sandbox_project do |sandbox, project|
      assert_equal "foo", Build.new(project, "foo").abbreviated_label
      assert_equal "foobarb", Build.new(project, "foobarbaz").abbreviated_label
      assert_equal "foo.bar", Build.new(project, "foo.bar").abbreviated_label
      assert_equal "foobarb.quux", Build.new(project, "foobarbaz.quux").abbreviated_label
    end
  end

end
