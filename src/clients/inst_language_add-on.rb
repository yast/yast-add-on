# encoding: utf-8

# File:	clients/inst_language_add-on.ycp
# Authors:	Lukas Ocilka <locilka@suse.cz>
# Summary:	Template client for language Add-On products
#
# This is a template for Language Add-Ons. It can be either called
# from the installation.xml in the root ("/") of the product or
# called from command-line for testing purposes:
# `yast2 inst_language_add-on.ycp "$[]" url_to_add_on_source`.
#
# $Id$
module Yast
  class InstLanguageAddOnClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"
      Yast.import "Kernel"
      Yast.import "Language"
      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Popup"

      textdomain "add-on"

      Wizard.CreateDialog
      Builtins.y2milestone(
        "====================[ Language Add-On Script ]===================="
      )
      @ret = MainFunction()
      Builtins.y2milestone(
        "====================[ Language Add-On Script ]===================="
      )
      Wizard.CloseDialog

      if @ret == 0
        return :next
      else
        return :abort
      end
    end

    # Returns the list of available languages. It is based on the
    # "LINGUAS" entry in the /content file. Returns nil if something
    # is wrong.
    #
    # @return [Array<String>] supported languages
    #   (e.g., ["af", "ar", "be_BY", "bg", "ca", "cs", "cy", "da", "el", "et", "fi"])
    def GetListOfSupportedLanguages(source)
      content_file = Pkg.SourceProvideSignedFile(source, 1, "/content", false)
      if content_file == nil || content_file == ""
        Builtins.y2error("There is no content file!")
        return nil
      end

      SCR.RegisterAgent(
        path(".media.content"),
        term(
          :ag_ini,
          term(
            :IniAgent,
            content_file,
            {
              "options"  => ["read_only", "global_values", "flat"],
              "comments" => ["^#.*", "^[ \t]*$"],
              "params"   => [
                {
                  "match" => [
                    "^[ \t]*([a-zA-Z0-9_.]+)[ \t]*(.*)[ \t]*$",
                    "%s %s"
                  ]
                }
              ]
            }
          )
        )
      )
      supported_languages = Builtins.tostring(
        SCR.Read(path(".media.content.LINGUAS"))
      )
      if supported_languages == nil || supported_languages == ""
        Builtins.y2error("No languages [LINGUAS] defined!")
        return nil
      end

      Builtins.y2milestone("Languages found: %1", supported_languages)
      SCR.UnregisterAgent(path(".media.content"))

      Builtins.splitstring(supported_languages, " ")
    end

    # Solves dependencies and installs packages
    def Install(languages_to_install)
      languages_to_install = deep_copy(languages_to_install)
      Builtins.y2milestone(
        "Installing packages for languages: %1",
        languages_to_install
      )
      Pkg.SetAdditionalLocales(languages_to_install)

      Builtins.y2milestone("Solving dependencies")
      if Pkg.PkgSolve(true) != true
        Builtins.y2error("Cannot solve dependencies")
        return false
      end

      Builtins.y2milestone("Installing packages")
      WFM.call("inst_rpmcopy")

      Kernel.InformAboutKernelChange

      Popup.Message(
        # TRANSLATORS: popup message
        _("Installation of the Language Extension has been finished.")
      )

      true
    end

    # Only when WFM::Args[1] contains an URL to be added
    def InitFunction
      args = WFM.Args
      Builtins.y2milestone("Args: %1", args)
      add_on_url = Builtins.tostring(Ops.get_string(args, 1, ""))

      if add_on_url == ""
        Builtins.y2milestone(
          "No URL given as an argument, not initializing source."
        )
        return
      end

      Builtins.y2milestone("Using URL: '%1'", add_on_url)

      Yast.import "PackageCallbacks"
      Yast.import "SourceManager"

      PackageCallbacks.InitPackageCallbacks

      Pkg.TargetInit("/", true)
      Pkg.SourceStartManager(true)

      SourceManager.createSource(add_on_url)

      nil
    end

    # Dialog definitions -->

    def Dialog_Init
      Wizard.SetContentsButtons(
        # TRANSLATORS: dialog caption
        _("Add-On Product Installation"),
        # TRANSLATORS: dialog content - a very simple label
        Label(_("Initializing...")),
        # TRANSLATORS: help text
        _("<p>Initializing add-on products...</p>"),
        Label.BackButton,
        Label.NextButton
      )
      Wizard.SetTitleIcon("yast-language")
      Wizard.DisableBackButton
      Wizard.DisableAbortButton
      Wizard.DisableNextButton

      nil
    end




    def Dialog_SelectLanguagesUI(known_languages, already_installed_languages)
      items = []
      pre_selected_languages = []
      pre_selected = nil

      # for each language supported on the medium
      Builtins.foreach(known_languages.value) do |short, long|
        # installed is 'de' or 'cs' or 'zh'
        if Builtins.contains(already_installed_languages.value, short)
          pre_selected = true 
          # installed is 'de_XY' or 'cs_AB' or 'zh_CD'
          # but not on the medium, find similar
        elsif Ops.greater_than(Builtins.size(short), 2)
          language_substring = Builtins.substring(short, 0, 2)
          if Builtins.contains(
              already_installed_languages.value,
              language_substring
            )
            pre_selected = true
          else
            pre_selected = false
          end
        else
          pre_selected = false
        end
        if pre_selected
          pre_selected_languages = Builtins.add(
            pre_selected_languages,
            Builtins.sformat("%1 (%2)", short, long)
          )
        end
        items = Builtins.add(items, Item(Id(short), long, pre_selected))
      end
      Builtins.y2milestone("Preselected languages: %1", pre_selected_languages)

      items = Builtins.sort(items) do |x, y|
        Ops.less_than(Ops.get_string(x, 1, ""), Ops.get_string(y, 1, ""))
      end
      Wizard.SetContentsButtons(
        # TRANSLATORS: dialog caption
        _("Add-On Product Installation"),
        VBox(
          HBox(
            HStretch(),
            MultiSelectionBox(
              Id("languages"),
              # TRANSLATORS:: multi-selection box
              _("&Select Language Extensions to Be Installed"),
              items
            ),
            HStretch()
          )
        ),
        # TRANSLATORS: help text
        _(
          "<p>Select the language extensions to be installed then click <b>OK</b>.</p>"
        ),
        Label.BackButton,
        Label.OKButton
      )
      Wizard.SetTitleIcon("yast-language")
      Wizard.DisableBackButton
      Wizard.EnableAbortButton
      Wizard.EnableNextButton

      selected_languages = nil
      ret = nil
      while true
        ret = UI.UserInput

        if ret == :cancel || ret == :abort
          if Popup.YesNo(
              # TRANSLATORS: popup question
              _(
                "Are you sure you want to abort the add-on product installation?"
              )
            )
            selected_languages = []
            break
          end
        elsif ret == :next
          selected_languages = Convert.convert(
            UI.QueryWidget(Id("languages"), :SelectedItems),
            :from => "any",
            :to   => "list <string>"
          )
          if Builtins.size(selected_languages) == 0
            if !Popup.YesNo(
                _(
                  "There are no selected languages to be installed.\nAre you sure you want to abort the installation?"
                )
              )
              next
            else
              Builtins.y2warning(
                "User decided not to install any language support."
              )
            end
          end

          break
        end
      end

      deep_copy(selected_languages)
    end




    def Dialog_SelectLanguages(available_languages, already_installed_languages)
      available_languages = deep_copy(available_languages)
      if available_languages == nil || available_languages == []
        Builtins.y2error("No availabel languages")
        return nil
      elsif Builtins.size(available_languages) == 1
        Builtins.y2milestone(
          "Only one language available, using %1",
          available_languages
        )
        return deep_copy(available_languages)
      else
        known_languages = Language.GetLanguagesMap(false)

        short_to_lang = {}
        Builtins.foreach(available_languages) do |one_lang|
          # full xx_YY
          if Ops.get(known_languages, one_lang) != nil
            Ops.set(
              short_to_lang,
              one_lang,
              Ops.get_string(known_languages, [one_lang, 4], "")
            ) 
            # xx only without _YY
          else
            found = false
            Builtins.foreach(known_languages) do |lang_short, lang_params|
              if Builtins.regexpmatch(
                  lang_short,
                  Builtins.sformat("%1_.*", one_lang)
                )
                Ops.set(
                  short_to_lang,
                  one_lang,
                  Builtins.tostring(Ops.get_string(lang_params, 4, ""))
                )
                found = true
                raise Break
              end
            end
            if !found
              Builtins.y2warning("Couldn't find language for '%1'", one_lang)
              # TRANSLATORS: multiselection box item, %1 stands for 'ar', 'mk', 'zh_TW'
              # it used only as a fallback
              Ops.set(
                short_to_lang,
                one_lang,
                Builtins.sformat(_("Language %1"), one_lang)
              )
            end
          end
        end

        Builtins.y2milestone("%1", short_to_lang)
        selected_languages = (
          short_to_lang_ref = arg_ref(short_to_lang);
          already_installed_languages_ref = arg_ref(
            already_installed_languages.value
          );
          _Dialog_SelectLanguagesUI_result = Dialog_SelectLanguagesUI(
            short_to_lang_ref,
            already_installed_languages_ref
          );
          short_to_lang = short_to_lang_ref.value;
          already_installed_languages.value = already_installed_languages_ref.value(
          );
          _Dialog_SelectLanguagesUI_result
        )

        return deep_copy(selected_languages)
      end
    end

    # Dialog definitions <--

    def MainFunction
      Dialog_Init()

      # This call can be removed
      InitFunction()

      # Finding out the source, can be also used AddOnProduct::src_id
      # but this is better for testing
      all_sources = Pkg.SourceGetCurrent(true)
      all_sources = Builtins.sort(all_sources) { |x, y| Ops.less_than(x, y) }
      source = Ops.get(
        all_sources,
        Ops.subtract(Builtins.size(all_sources), 1),
        -1
      )
      Pkg.SourceSetEnabled(source, true)

      # one language   -> preselect it and install
      # more languages -> let user decides
      available_languages = GetListOfSupportedLanguages(source)
      if available_languages == nil || available_languages == []
        Builtins.y2error("No languages available!")
        return 10
      end

      # bugzilla #217052
      # some languages should be pre-selected (already installed, at least partly)
      installed_languages = Pkg.ResolvableProperties("", :language, "")
      already_installed_languages = []
      Builtins.foreach(installed_languages) do |language|
        if Ops.get(language, "status") == :installed
          if Ops.get(language, "name") != nil
            already_installed_languages = Builtins.add(
              already_installed_languages,
              Ops.get_string(language, "name", "")
            )
          else
            Builtins.y2error("Language %1 has no 'name'", language)
          end
        end
      end

      Builtins.y2milestone(
        "Already installed languages: %1",
        already_installed_languages
      )
      selected_languages = (
        already_installed_languages_ref = arg_ref(already_installed_languages);
        _Dialog_SelectLanguages_result = Dialog_SelectLanguages(
          available_languages,
          already_installed_languages_ref
        );
        already_installed_languages = already_installed_languages_ref.value;
        _Dialog_SelectLanguages_result
      )
      if selected_languages == nil || selected_languages == []
        Builtins.y2warning("User did not select any language, finishing...")
        return 15
      end

      if Install(selected_languages) != true
        Builtins.y2error("Error occured during installation")
        return 20
      end

      0
    end
  end
end

Yast::InstLanguageAddOnClient.new.main
