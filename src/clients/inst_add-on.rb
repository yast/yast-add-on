# encoding: utf-8

# File:	clients/inst_add-on.ycp
# Package:	yast2-add-on
# Summary:	Select add-on products for installation
# Authors:	Jiri Srain <jsrain@suse.de>
#
module Yast
  class InstAddOnClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "add-on"

      Yast.import "AddOnProduct"
      Yast.import "GetInstArgs"
      Yast.import "Packages"
      Yast.import "PackageCallbacks"
      Yast.import "Popup"
      Yast.import "ProductControl"
      Yast.import "Report"
      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Installation"
      Yast.import "Linuxrc"
      Yast.import "String"

      Yast.include self, "add-on/add-on-workflow.rb"

      if AddOnProduct.skip_add_ons
        Builtins.y2milestone("Skipping add-ons (as requested before)")
        return :auto
      end

      @argmap = GetInstArgs.argmap

      Packages.SelectProduct

      PackageCallbacks.SetMediaCallbacks

      # add add-ons specified on the kernel command line
      @addon_opt = Linuxrc.InstallInf("addon")

      # add the add-ons just once, skip adding if any add-on is
      # already present (handle going back and forth properly)
      if @addon_opt != nil && AddOnProduct.add_on_products == []
        Builtins.y2milestone("Specified extra add-ons via kernel cmdline")

        # store the add-ons list into a temporary file
        @tmp_dir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
        @tmp_file = Ops.add(@tmp_dir, "/tmp_addon_list")
        # each add-on on a separate line
        @addons = String.Replace(@addon_opt, ",", "\n")

        # network setup is needed for local media installation (e.g. DVD) with remote Add-ons
        @ret2 = NetworkSetupForAddons(Builtins.splitstring(@addons, "\n"))

        return @ret2 if Builtins.contains([:back, :abort], @ret2)

        SCR.Write(path(".target.string"), @tmp_file, @addons)

        # import the add-ons from the temporary file
        AddOnProduct.AddPreselectedAddOnProducts(
          [{ "file" => @tmp_file, "type" => "plain" }]
        )

        # remove the temporary file
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("/bin/rm -rf '%1'", String.Quote(@tmp_file))
        )
      end

      # the module was started because of the kernel command line option
      # so finish it after adding the add-ons, no UI is actually needed
      return :auto if Installation.add_on_selected == false

      @ret = RunAddOnMainDialog(
        GetInstArgs.enable_back,
        GetInstArgs.enable_next,
        true,
        Label.BackButton,
        Label.NextButton,
        Label.AbortButton,
        true
      )

      @ret 

      # EOF
    end

    # Ask to user to configure network for installing remote addons.
    # User is aske when there is a remote add-on found and the network
    # is not running yet.
    #
    # @param addon_urls list of URLs
    # @return symbol user input result (`next, `back or `abort)
    def NetworkSetupForAddons(addon_urls)
      addon_urls = deep_copy(addon_urls)
      # protocols locally available (no network needed)
      local_protocols = ["cd", "dvd", "hd"]

      # is this CD/DVD/HDD installation?
      if Builtins.contains(
          local_protocols,
          Builtins.tolower(Linuxrc.InstallInf("InstMode"))
        )
        # is there any remote addon requiring network setup?
        network_needed = false
        Builtins.foreach(addon_urls) do |url|
          # is it a remote protocol?
          if !Builtins.contains(
              local_protocols,
              Builtins.tolower(Ops.get_string(URL.Parse(url), "scheme", ""))
            )
            network_needed = true
            raise Break
          end
        end 


        if network_needed
          # check and setup network
          ret = Convert.to_symbol(WFM.CallFunction("inst_network_check", []))
          Builtins.y2milestone("inst_network_check ret: %1", ret)

          return ret if Builtins.contains([:back, :abort], ret)
        end
      end

      :next
    end
  end
end

Yast::InstAddOnClient.new.main
