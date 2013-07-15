# -*- coding: utf-8 -*-
#--
# NewsCrawler - a website crawler
#
# Copyright (C) 2013 - Hà Quang Dương <contact@haqduong.net>
#
# This file is part of NewsCrawler.
#
# NewsCrawler is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# NewsCrawler is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NewsCrawler.  If not, see <http://www.gnu.org/licenses/>.
#++

require 'celluloid'
require 'nokogiri'

require 'news_crawler/storage/raw_data'
require 'news_crawler/url_helper'
require 'news_crawler/crawler_module'

module NewsCrawler
  module LinkSelector
    # Select all link from same domain.
    # Domain is got from database
    class SameDomainSelector
      include NewsCrawler::URLHelper
      extend NewsCrawler::URLHelper

      include NewsCrawler::CrawlerModule
      include Celluloid

      # Create new selector with queue
      # URL's selected is put back into queue
      # @param [ Fixnum  ] max_depth maxinum depth to crawl
      # @param [ Boolean ] start_on_create whether start selector immediately
      def initialize(max_depth = -1, start_on_create = true)
        @max_depth = max_depth
        @wait_time = 1
        @status = :running
        @stoping = false
        run if start_on_create
      end

      # Extract url from page
      def extract_url(url)
        doc      = RawData.find_by_url(url)
        html_doc = Nokogiri::HTML(doc)
        results  = []

        inner_url = html_doc.xpath('//a').collect { | a_el |
          temp_url = (a_el.attribute 'href').to_s
          if (!temp_url.nil?) && (temp_url[0] == '/')
            temp_url = url + temp_url
          end
          temp_url
        }

        inner_url.delete_if { | url |
            (url.nil?) || (url.size == 0) || (url == '#')
        }

        # select url from same domain
        inner_url.select { | o_url |
          if (same_domain?(o_url, url))
            if (!SameDomainSelector.exclude?(o_url))
              begin
                URLQueue.add(o_url, url)
                results << [o_url, url]
              rescue URLQueue::DuplicateURLError => e
              end
            else
              # TODO Log here
            end
          end
        }
      end

      def run
        @status = :running
        return if @stoping
        while !@stoping
          url = next_unprocessed(@max_depth)
          while (url.nil?)
            wait_for_url
            url = next_unprocessed(@max_depth)
          end
          puts "Processing #{url}"
          extract_url(url)
          mark_processed(url)
        end
      end

      # Test whether url is excluded
      # @param [ String ] url
      # @return [ Boolean ] true if url is excluded, false otherwise
      def self.exclude?(url)
        config       = SimpleConfig.for :same_domain_selector
        exclude_list = []
        url_domain   = get_url_path(url)[:domain]
        begin
          exclude_group = config.exclude
        rescue NoMethodError => e
          return false
        end

        exclude_group.to_hash.keys.each do | url_e |
          if url_domain.to_s.end_with? url_e.to_s
            exclude_list = config.exclude.get(url_e)
            break
          end
        end

        if exclude_list.count == 0
          return false
        end

        url.split('/').each do | part |
          if exclude_list.include? part
            return true
          end
        end
        return false
      end

      # Graceful terminate this selector
      def graceful_terminate
        @stoping = true
        while @status == :running
          sleep(1)
        end
      end

      private
      # Waiting for new urls're added to queue, using backoff algorithms
      def wait_for_url
        @status = :waiting
        sleep @wait_time
        if @wait_time < 30
          @wait_times = @wait_time * 2
        end
      end
    end
  end
end
