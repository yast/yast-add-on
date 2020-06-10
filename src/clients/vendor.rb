# File:  clients/vendor.ycp
# Package:  yast2-add-on
# Summary:  Load vendor driver CD
# Authors:  Klaus Kaempf <kkaempf@suse.de>
#
# $Id$

require "y2packager/resolvable"
module Yast
  class VendorClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "add-on"

      Yast.import "Arch"
      Yast.import "Installation"
      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Wizard"
      Yast.import "GetInstArgs"
      Yast.import "Mode"
      Yast.import "CommandLine"

      # Bugzilla #269911, CommanLine "support"
      # argmap is only a map, CommandLine uses string parameters
      if Builtins.size(GetInstArgs.argmap) == 0 &&
          Ops.greater_than(Builtins.size(WFM.Args), 0)
        Mode.SetUI("commandline")
        Builtins.y2milestone("Mode CommandLine not supported, exiting...")
        # TRANSLATORS: error message - the module does not provide command line interface
        CommandLine.Print(
          _("There is no user interface available for this module.")
        )
        return :auto
      end

      @language = UI.GetLanguage(true)

      @is_mounted = false

      #------------------------------------------------------------

      @arg_n = Ops.subtract(Builtins.size(WFM.Args), 1)

      @default_device = "/dev/cdrom"

      while Ops.greater_or_equal(@arg_n, 0)
        if Builtins.substring(Convert.to_string(WFM.Args(@arg_n)), 0, 1) == "/"
          @default_device = Convert.to_string(WFM.Args(@arg_n))
        end
        @arg_n = Ops.subtract(@arg_n, 1)
      end

      @result = nil

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("org.opensuse.yast.Vendor")
      Wizard.HideAbortButton

      # VENDOR: main screen heading
      @title = _("Vendor Driver CD")
      Wizard.SetContents(@title, Empty(), "", true, true)

      # free mount point
      SCR.Execute(path(".target.umount"), Installation.sourcedir)

      # try to mount device

      while SCR.Execute(
        path(".target.mount"),
        [@default_device, Installation.sourcedir]
      ) == false
        # VENDOR: cant mount /dev/cdrom popup
        if !Popup.ContinueCancel(_("Please insert the vendor CD-ROM"))
          UI.CloseDialog
          return :abort
        end
      end

      @is_mounted = true

      # CD is mounted. Check contents.

      @cdpath = Installation.sourcedir

      # get directory on update disk from installation (value from install.inf)
      #
      # if not set, determine directory from installed products
      #

      @update_dir = Convert.to_string(
        SCR.Read(path(".target.string"), ["/var/lib/YaST2/vendor_update", ""])
      )
      if @update_dir != ""
        @cdpath = Ops.add(@cdpath, @update_dir)
      else
        Pkg.TargetInit("/", false)

        base = Y2Packager::Resolvable.find(kind:     :product,
                                           status:   :installed,
                                           category: "base")
        if base.empty?
          # fallback
          base = Y2Packager::Resolvable.find(kind:   :product,
                                             status: :installed)
        end
        version = base[0] ? base[0].version_version : ""

        Builtins.y2milestone("Trying %1", @cdpath)
        @dirlist2 = Convert.to_list(SCR.Read(path(".target.dir"), @cdpath))

        if Ops.less_or_equal(Builtins.size(@dirlist2), 0) ||
            !Builtins.contains(@dirlist2, "linux")
          # VENDOR: vendor cd contains wrong data
          return wrong_cd(
            _("Could not find driver data on the CD-ROM.\nAborting now."),
            @is_mounted
          )
        end

        @cdpath = Ops.add(@cdpath, "/linux")

        Builtins.y2milestone("Trying %1", @cdpath)

        @dirlist2 = Convert.to_list(SCR.Read(path(".target.dir"), @cdpath))
        if Ops.less_or_equal(Builtins.size(@dirlist2), 0) ||
            !Builtins.contains(@dirlist2, "suse")
          # VENDOR: vendor cd contains wrong data
          return wrong_cd(
            _("Could not find driver data on the CD-ROM.\nAborting now."),
            @is_mounted
          )
        end

        @cdpath = Ops.add(
          Ops.add(Ops.add(Ops.add(@cdpath, "/suse/"), Arch.architecture), "-"),
          version
        )
      end

      Builtins.y2milestone("Trying %1", @cdpath)

      @dirlist = Convert.convert(
        SCR.Read(path(".target.dir"), @cdpath),
        from: "any",
        to:   "list <string>"
      )
      if Ops.less_or_equal(Builtins.size(@dirlist), 0)
        # VENDOR: vendor cd doesn't contain data for current system and linux version
        return wrong_cd(
          _(
            "The CD-ROM data does not match the running Linux system.\nAborting now.\n"
          ),
          @is_mounted
        )
      end

      Builtins.y2milestone("found %1", @dirlist)

      # filter files ending in .inst (allow .ins for dos :-})

      @instlist = []
      Builtins.foreach(@dirlist) do |fname|
        splitted = Builtins.splitstring(fname, ".")
        if Builtins.size(splitted) == 2 &&
            Builtins.substring(Ops.get(splitted, 1, ""), 0, 3) == "ins"
          @instlist = Builtins.add(@instlist, Ops.get(splitted, 0, ""))
        end
      end

      Builtins.y2milestone("inst %1", @instlist)

      if Ops.less_or_equal(Builtins.size(@dirlist), 0)
        # VENDOR: vendor cd contains wrong data
        return wrong_cd(
          _("Could not find driver data on the CD-ROM.\nAborting now."),
          @is_mounted
        )
      end

      @inst_count = 0

      @short_lang = ""
      @short_lang = Builtins.substring(@language, 0, 2) if Ops.greater_than(Builtins.size(@language), 2)

      # try to load .inst files, try with (xx_XX) ISO language first,
      # then with 2 char language code
      # show data from matching files

      Builtins.foreach(@instlist) do |fname|
        # try full ISO language code first
        description = Convert.to_string(
          SCR.Read(
            path(".target.string"),
            Ops.add(
              Ops.add(
                Ops.add(Ops.add(Ops.add(@cdpath, "/"), fname), "-"),
                @language
              ),
              ".desc"
            )
          )
        )
        # try with 2 char language code
        if Ops.less_or_equal(Builtins.size(description), 0)
          description = Convert.to_string(
            SCR.Read(
              path(".target.string"),
              Ops.add(
                Ops.add(
                  Ops.add(Ops.add(Ops.add(@cdpath, "/"), fname), "-"),
                  @short_lang
                ),
                ".desc"
              )
            )
          )
        end
        # try without language code
        if Ops.less_or_equal(Builtins.size(description), 0)
          description = Convert.to_string(
            SCR.Read(
              path(".target.string"),
              Ops.add(Ops.add(Ops.add(@cdpath, "/"), fname), ".desc")
            )
          )
        end
        # show contents
        if Ops.greater_than(Builtins.size(description), 0)
          if Popup.YesNo(description)
            # VENDOR: dialog heading
            Wizard.SetContents(
              @title,
              HVCenter(Label(_("Installing driver..."))),
              "",
              true,
              true
            )
            inst_result = run_inst(@cdpath, Ops.add(fname, ".inst"))
            if inst_result == 0
              @inst_count = Ops.add(@inst_count, 1)
            else
              # VENDOR: popup if installation of driver failed
              Popup.Message(
                _(
                  "The installation failed.\nContact the address on the CD-ROM.\n"
                )
              )
            end
            Wizard.SetContents(@title, Empty(), "", true, true)
          end
        end
      end

      @result_message = ""
      @result_message = if Ops.greater_than(@inst_count, 0)
        # VENDOR: message box with number of drivers installed
        Builtins.sformat(
          _("Installed %1 drivers from CD"),
          @inst_count
        )
      else
        # VENDOR: message box with error text
        _(
          "No driver data found on the CD-ROM.\nAborting now."
        )
      end

      Popup.Message(@result_message)

      # free mount point
      SCR.Execute(path(".target.umount"), Installation.sourcedir)

      UI.CloseDialog
      :ok

      # EOF
    end

    # display message if the CD seems to be wrong

    def wrong_cd(reason, must_umount)
      Popup.Message(reason)
      if must_umount
        # free mount point
        SCR.Execute(path(".target.umount"), Installation.sourcedir)
      end
      UI.CloseDialog
      :abort
    end

    # run <name>.inst file
    # return 0 on success

    def run_inst(fpath, fname)
      Builtins.y2milestone("run_inst %1/%2", fpath, fname)

      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      SCR.Execute(
        path(".target.bash"),
        Ops.add(
          Ops.add(Ops.add(Ops.add(Ops.add("/bin/cp ", fpath), "/"), fname), " "),
          tmpdir
        )
      )

      # force it to be readable and executable
      SCR.Execute(
        path(".target.bash"),
        Ops.add(Ops.add(Ops.add("/bin/chmod 774 ", tmpdir), "/"), fname)
      )

      result = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(Ops.add(Ops.add("(cd ", tmpdir), "; ./"), fname),
                " "
              ),
              fpath
            ),
            ")"
          )
        )
      )
      SCR.Execute(path(".target.remove"), Ops.add(Ops.add(tmpdir, "/"), fname))

      result
    end
  end
end

Yast::VendorClient.new.main
