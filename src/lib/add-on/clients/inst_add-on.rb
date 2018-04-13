# encoding: utf-8

# File:	clients/inst_add-on.ycp
# Package:	yast2-add-on
# Summary:	Select add-on products for installation
# Authors:	Jiri Srain <jsrain@suse.de>
#

require "tempfile"

module Yast
  # @note This client should not be called from other clients directly
  #  via WFM.call (only from the control.xml file), it can restart the workflow
  #  from the next step and return to the caller AFTER the complete workflow
  #  is finished (or aborted)
  class InstAddOnClient < Client
    include Yast::Logger

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
      Yast.import "URL"

      Yast.include self, "add-on/add-on-workflow.rb"
      Yast.include self, "packager/repositories_include.rb"

      if AddOnProduct.skip_add_ons
        Builtins.y2milestone("Skipping add-ons (as requested before)")
        return :auto
      end

      @argmap = GetInstArgs.argmap

      Packages.SelectProduct

      PackageCallbacks.SetMediaCallbacks

      # add add-ons specified on the kernel command line
      addon_opt = Linuxrc.InstallInf("addon")

      # the "addon" boot option is present
      if addon_opt != nil
        missing_addons = addon_opt.split(",") - current_addons

        # add the add-ons just once, skip adding if all add-ons are
        # already present (handle going back and forth properly)
        if missing_addons.empty?
          log.info("All kernel cmdline addons already present")
        else
          # do not reveal the URL passwords in the log
          missing_addons_log = missing_addons.map { |a| URL.HidePassword(a) }
          log.info("Adding extra add-ons from kernel cmdline: #{missing_addons_log}")

          # network setup is needed when installing from a local medium (DVD) with remote Add-ons
          ret = NetworkSetupForAddons(missing_addons)
          return ret if Builtins.contains([:back, :abort], ret)

          plaindir, download, name, alias_ = false, true, "", ""
          missing_addons.each do |url|
            sources_before = Pkg.SourceGetCurrent(false)
            Builtins.y2milestone("Sources before adding new one: %1", sources_before)

            next if instsys_dvd?(url) && !AddOnProduct.AskForCD(url, name)
            createSourceImpl(url, plaindir, download, name, alias_)

            activate_addon_changes(sources_before)
          end
          InstallProduct()
        end
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

      if @ret == :next
        # be careful when calling this client from other modules, this will
        # start the workflow from the next step and THEN return back
        # to the caller
        @ret = ProductControl.RunFrom(
          Ops.add(ProductControl.CurrentStep, 1),
          true
        )
        @ret = :finish if @ret == :next
      end

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

    # get the URLs of the all present add-ons
    # @return [Array<String>] list of URLs (empty list if no add-on defined)
    def current_addons
      AddOnProduct.add_on_products.map do |addon|
        Pkg.SourceURL(addon["media"])
      end
    end

    # URL schemas to be considered as CD/DVD
    DVD_SCHEMES = ["cd", "dvd"].freeze

    # Determine whether the URL points to the installation CD/DVD
    #
    # @param url [String] Add-on URL
    # @return [Boolean] true if it points to the installation CD/DVD
    def instsys_dvd?(url)
      scheme = URL.Parse(url)["scheme"]
      return false unless DVD_SCHEMES.include?(scheme.downcase)

      addon_devices = devices_from_url(url)
      addon_devices.include?(instsys_device)
    end

    # instsys device
    #
    # @return [String] instsys device; nil if the device could not be
    #   determined (for instance, when using a network based installation media)
    def instsys_device
      return @instsys_device if @instsys_device
      @instsys_device = devices_from_url(InstURL.installInf2Url).first
    end

    # Real device from an URL
    #
    # Symbolic links are resolved, so real devices are returned.
    #
    # @param url [String] URL
    # @return [Array<String>] Paths to the devices. If no valid devices are found,
    #   it will return an empty array.
    def devices_from_url(url)
      parsed = URL.Parse(url)
      params = URL.MakeMapFromParams(parsed["query"])
      return [] unless params["devices"]
      devices = params["devices"].split(",") # MakeMapFromParams unescapes %2C

      devices.each_with_object([]) do |device, all|
        begin
          # File.realpath resolves symlinks (e.g. /dev/by-* to real devices like /dev/srX)
          all << File.realpath(device)
        rescue Errno::ENOENT
        end
      end
    end
  end
end
