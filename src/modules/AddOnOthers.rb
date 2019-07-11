# encoding: utf-8
require "yast"
require "y2packager/resolvable"

# Yast namespace
module Yast
  # This module provides integration of the add-on products

  class AddOnOthersClass < Module
           
    include Yast::Logger

    #     add_on_others = [
    #        {
    #          "media" => 4, # ID of the source
    #          "name" : "openSUSE version XX.Y",
    #          "media_url"=>"dvd:/?devices=/dev/sr1"
    #          ....
    #        },
    #        ...
    #      ]
    attr_reader :add_on_others

    def main
      Yast.import "Pkg"
      textdomain "packager"      

      @add_on_others = []
    end

    def Read
      # Removing all repos which have installed based products
      # and add-on products.
      all_products = Y2Packager::Resolvable.find(kind: :product, status: :available)
      installed_products = all_products.select do |p|
        Y2Packager::Resolvable.any?(kind: :product, status: :installed, name: p.name)
      end
      installed_src_ids = installed_products.map{ |p| p.source }.uniq
      other_repo_ids = Pkg.SourceGetCurrent(true) - installed_src_ids
      @add_on_others = other_repo_ids.map{ |id| Pkg.SourceGeneralData(id) }
    end

    # Returns all enabled user added repos which are not base products or add-on products.
    #
    # @return [Hash] User defined repos.
    #
    # @example This is an XML file created from exported map:
    #      <add-on>
    #        <add_on_others config:type="list">
    #          <listentry>
    #            <media_url>ftp://server.name/.../</media_url>
    #            <alias>alias name</alias>
    #            <priority config:type="integer">20</priority>
    #            <name>Repository name</name>
    #            <product_dir>/</product_dir>
    #          </listentry>
    #          ...
    #        </add_on_others>
    #      </add-on>
    def Export
      others = @add_on_others.map do |p|
        { "media_url"   => p["url"],
          "alias"       => p["alias"],
          "priority"    => p["priority"],
          "name"        => p["name"],
          "product_dir" => p["product_dir"] }
      end
      { "add_on_others" => others }
    end

    publish function: :Export, type: "map ()"
    publish function: :Read, type: "map()"
  end

  AddOnOthers = AddOnOthersClass.new
  AddOnOthers.main
end

