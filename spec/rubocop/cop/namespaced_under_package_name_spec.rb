# @mission Foundation
# @team Product Infrastructure
# frozen_string_literal: true

RSpec.describe RuboCop::Cop::PackageProtections::NamespacedUnderPackageName do
  subject(:cop) { described_class.new }
  let(:global_namespaces) { {} }

  before do
    write_package_yml('packs/apples', global_namespaces: global_namespaces)
    PackageProtections.bust_cache!
  end

  context 'global namespaces are not explicitly defined' do
    context 'when file establishes different namespace' do
      let(:source) do
        <<~RUBY
          class Tool
          ^ `packs/apples` prevents modules/classes that are not submodules of the package namespace. Should be namespaced under `Apples` with path `packs/apples/app/services/apples/tool.rb`. See https://go/packwerk_cheatsheet_namespaces for more info.
          end
        RUBY
      end

      it { expect_offense source, Pathname.pwd.join(write_file('packs/apples/app/services/tool.rb')).to_s }
    end

    context 'when file is in different namespace' do
      let(:source) do
        <<~RUBY
          module Tools
          ^ `packs/apples` prevents modules/classes that are not submodules of the package namespace. Should be namespaced under `Apples` with path `packs/apples/app/services/apples/tools/blah.rb`. See https://go/packwerk_cheatsheet_namespaces for more info.
            class Blah
            end
          end
        RUBY
      end

      it { expect_offense source, Pathname.pwd.join(write_file('packs/apples/app/services/tools/blah.rb')).to_s }
    end

    context 'when file establishes primary namespace' do
      let(:source) do
        <<~RUBY
          module Apples
          end
        RUBY
      end

      it { expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/app/services/apples.rb')).to_s }
    end

    context 'when file is in package namespace' do
      let(:source) do
        <<~RUBY
          module Apples
            class Tool
            end
          end
        RUBY
      end

      it { expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/app/services/apples/tool.rb')).to_s }
    end
  end

  context 'global namespaces is defined and is same as package name' do
    let(:global_namespaces) { %w[Apples] }

    context 'when file establishes different namespace' do
      let(:source) do
        <<~RUBY
          class Tool
          ^ `packs/apples` prevents modules/classes that are not submodules of the package namespace. Should be namespaced under `Apples` with path `packs/apples/app/services/apples/tool.rb`. See https://go/packwerk_cheatsheet_namespaces for more info.
          end
        RUBY
      end

      it { expect_offense source, Pathname.pwd.join(write_file('packs/apples/app/services/tool.rb')).to_s }
    end

    context 'when file is in different namespace' do
      let(:source) do
        <<~RUBY
          module Tools
          ^ `packs/apples` prevents modules/classes that are not submodules of the package namespace. Should be namespaced under `Apples` with path `packs/apples/app/services/apples/tools/blah.rb`. See https://go/packwerk_cheatsheet_namespaces for more info.
            class Blah
            end
          end
        RUBY
      end

      it { expect_offense source, Pathname.pwd.join(write_file('packs/apples/app/services/tools/blah.rb')).to_s }
    end

    context 'when file establishes primary namespace' do
      let(:source) do
        <<~RUBY
          module Apples
          end
        RUBY
      end

      it { expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/app/services/apples.rb')).to_s }
    end

    context 'when file is in package namespace' do
      let(:source) do
        <<~RUBY
          module Apples
            class Tool
            end
          end
        RUBY
      end

      it { expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/app/services/apples/tool.rb')).to_s }
    end
  end

  context 'several global namespaces are provided' do
    let(:global_namespaces) { %w[AppleTrees ApplePies Ciders] }

    context 'when file establishes different namespace' do
      let(:source) do
        <<~RUBY
          class Tool
          ^ `packs/apples` prevents modules/classes that are not submodules of one of the allowed namespaces in `packs/apples/package.yml`. See https://go/packwerk_cheatsheet_namespaces for more info.
          end
        RUBY
      end

      it { expect_offense source, Pathname.pwd.join(write_file('packs/apples/app/services/tool.rb')).to_s }
    end

    context 'when file is in different namespace' do
      let(:source) do
        <<~RUBY
          module Tools
          ^ `packs/apples` prevents modules/classes that are not submodules of one of the allowed namespaces in `packs/apples/package.yml`. See https://go/packwerk_cheatsheet_namespaces for more info.
            class Blah
            end
          end
        RUBY
      end

      it { expect_offense source, Pathname.pwd.join(write_file('packs/apples/app/services/tools/blah.rb')).to_s }
    end

    context 'when file establishes primary namespace' do
      let(:source) do
        <<~RUBY
          module AppleTrees
          end
        RUBY
      end

      it { expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/app/services/apple_trees.rb')).to_s }
    end

    context 'when file is in package namespace' do
      let(:source) do
        <<~RUBY
          module Ciders
            class Tool
            end
          end
        RUBY
      end

      it { expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/app/services/ciders/tool.rb')).to_s }
    end
  end

  context 'file is a spec file' do
    let(:source) do
      <<~RUBY
        describe Forestry::Logging do
        end
      RUBY
    end

    it 'does not handle spec files and gracefully exits' do
      expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/spec/services/forestry/logging.rb')).to_s
    end
  end

  context 'when file is in different namespace and is in lib' do
    let(:source) do
      <<~RUBY
        module Tools
          class Blah
          end
        end
      RUBY
    end

    it 'does not handle spec files and gracefully exits' do
      expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/lib/services/tools/blah.rb')).to_s
    end
  end

  context 'when file establishes different namespace and is in concerns' do
    let(:source) do
      <<~RUBY
        class Tool
        ^ `packs/apples` prevents modules/classes that are not submodules of the package namespace. Should be namespaced under `Apples` with path `packs/apples/app/models/concerns/apples/tool.rb`. See https://go/packwerk_cheatsheet_namespaces for more info.
        end
      RUBY
    end

    it { expect_offense source, Pathname.pwd.join(write_file('packs/apples/app/models/concerns/tool.rb')).to_s }
  end

  context 'when file does not establish different namespace and is in concerns' do
    let(:source) do
      <<~RUBY
        class Apples
        end
      RUBY
    end

    it { expect_no_offenses source, Pathname.pwd.join(write_file('packs/apples/app/models/concerns/apples.rb')).to_s }
  end
end
