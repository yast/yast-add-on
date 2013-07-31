# encoding: utf-8

# File: inst_add-on_software.ycp
#
# Client providing the software overview/selection to be used
# in add-on products (their control files). If not set otherwise,
# (skip_installation), it also installs the selected resolvables
#
# Control File Example (installation.xml):
# <workflows config:type="list">
#   <workflow>
#     <stage>normal</stage>
#     <mode>installation,normal</mode>
#     <modules config:type="list">
#       ...
#       <module>
#         <label>Software Selection</label>
#         <name>inst_add-on_software</name>
#         <arguments>
#
#           <!--
#             Mode in which the Packager dialog opens up. See Available Modes.
#             The defalt mode is "patterns" if not set
#           -->
#           <sw_mode>patterns</sw_mode>
#
#           <!--
#             If set to "yes", packages (patterns/...) will not be installed
#             automatically. Default is "no" (packages will get installed).
#            -->
#           <skip_installation>yes</skip_installation>
#
#         </arguments>
#       </module>
#       ...
#     </modules>
#   </workflow>
# </workflows>
#
# Available Modes:
#   o patterns - list of all available (installed/selected/...) patterns
#   o search - dialog capable of searching through packages
#   o summary - installation summary
#   o repositories - list of enabled repositories (including the @System)
#
# See also BNC #469320
module Yast
  class InstAddOnSoftwareClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "Kernel"
      Yast.import "PackagesUI"
      Yast.import "GetInstArgs"
      Yast.import "ProductControl"
      Yast.import "ProductFeatures"
      Yast.import "Installation"

      return :auto if GetInstArgs.going_back

      @argmap = GetInstArgs.argmap
      Builtins.y2milestone("Client called with args: %1", @argmap)

      # Mapping of modes
      # module->arguments->sw_mode : UI_mode
      @modes = {
        "patterns"     => :patternSelector,
        "search"       => :searchMode,
        "summary"      => :summaryMode,
        "repositories" => :repoMode
      }

      # For sure
      Pkg.TargetInit(Installation.destdir, false)
      Pkg.SourceStartManager(true)

      @pcg_mode = Ops.get_string(@argmap, "sw_mode", "patterns")
      @run_in_mode = Ops.get(@modes, @pcg_mode, :summaryMode)
      Builtins.y2milestone(
        "Running package selector in mode %1/%2",
        @pcg_mode,
        @run_in_mode
      )

      # Call the package selector
      # Since yast2 >= 2.17.58
      @ret = PackagesUI.RunPackageSelector({ "mode" => @run_in_mode })
      Builtins.y2milestone("RunPackageSelector returned %1", @ret)

      @dialog_ret = :next

      @dialog_ret = :abort if @ret == :cancel

      if @ret == :accept || @ret == :ok
        # Add-on requires packages to be installed right now
        if Ops.get_boolean(@argmap, "skip_installation", false) != true
          Builtins.y2milestone("Selected resolvables will be installed now")

          if WFM.CallFunction(
              "inst_rpmcopy",
              [GetInstArgs.Buttons(false, false)]
            ) == :abort
            @dialog_ret = :abort
          else
            Kernel.InformAboutKernelChange
            Builtins.y2milestone("Done")
          end
        end
      end

      @dialog_ret
    end
  end
end

Yast::InstAddOnSoftwareClient.new.main
