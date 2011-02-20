#!/usr/bin/env ruby

# Copyright (c) 2011 Oleksandr Tymoshenko <gonzo@bluezbox.com>
# All rights reserved.

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.

# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

#
# Scraps all markets in App Store for new user reviews and sends them to email
# 

require 'rubygems'
require 'mechanize'
require 'iso_country_codes'
require 'json'
require 'digest/md5'
require 'pony'
require 'fsdb'

#
# Configuration part
#
# directory to store info about which reviews have been already sent 
DB_DIR = '/home/gonzo/reviews.db'
TO_EMAIL = 'info@yourdomain.com'
FROM_EMAIL = 'appstore@yourdomain.com'
# List of application ids
APPS = %w[413969927 333206277 383166877]
IDS_TABLE = 'review_ids'

#
# Actual code
#
class AppReview
  attr_accessor :author, :title, :text, :rating, :market, :application
  def initialize(args = {})
    args.each { |key,value| send("#{key}=", value) }  
  end
  def uid
    return Digest::MD5.hexdigest("#{@author}#{@title}#{@text}#{@rating}#{@market}")
  end
end

class AppStore
  @@markets = [
    'Argentina',
    'Armenia',
    'Australia',
    'Austria',
    'Belgium',
    'Botswana',
    'Brazil',
    'Bulgaria',
    'Canada',
    'Chile',
    'China',
    'Colombia',
    'Costa Rica',
    'Croatia',
    'Czech Republic',
    'Denmark',
    'Dominican Rep.',
    'Ecuador',
    'Egypt',
    'El Salvador',
    'Estonia',
    'Finland',
    'France',
    'Germany',
    'Greece',
    'Guatemala',
    'Honduras',
    'Hong Kong',
    'Hungary',
    'India',
    'Indonesia',
    'Ireland',
    'Israel',
    'Italy',
    'Jamaica',
    'Japan',
    'Jordan',
    'Kazakhstan',
    'Kenya',
    'Korea, Republic Of',
    'Kuwait',
    'Latvia',
    'Lebanon',
    'Lithuania',
    'Luxembourg',
    'Macao',
    'Macedonia, The Former Yugoslav Republic Of',
    'Madagascar',
    'Malaysia',
    'Mali',
    'Malta',
    'Mauritius',
    'Mexico',
    'Moldova, Republic Of',
    'Netherlands',
    'New Zealand',
    'Nicaragua',
    'Niger',
    'Norway',
    'Pakistan',
    'Panama',
    'Paraguay',
    'Peru',
    'Philippines',
    'Poland',
    'Portugal',
    'Qatar',
    'Romania',
    'Russia',
    'Saudi Arabia',
    'Senegal',
    'Singapore',
    'Slovakia',
    'Slovenia',
    'South Africa',
    'Spain',
    'Sri Lanka',
    'Sweden',
    'Switzerland',
    'Taiwan',
    'Thailand',
    'Tunisia',
    'Turkey',
    'Uganda',
    'United Kingdom',
    'United Arab Emirates',
    'Uruguay',
    'USA',
    'Venezuela',
    'Viet Nam'];

  def initialize
    @ua = Mechanize.new { |agent|
      agent.user_agent_alias = 'Mac Safari'
      # agent.log = Logger.new(STDERR)
    }
  end

  def get_all_reviews(appid)
    reviews = Array.new
    @@markets.each do |m|
      reviews += get_market_reviews(appid, m)
    end
    return reviews
  end

  def get_market_reviews(appid, market)
    reviews = Array.new
    iso = IsoCountryCodes.find(market.downcase, :fuzzy => true).alpha2.downcase
    json_info = @ua.get("http://ax.itunes.apple.com/WebObjects/MZStoreServices.woa/wa/wsLookup?id=#{appid}&country=#{iso}")
    result = JSON.parse(json_info.body)
    application = "app#{appid}"
    if result.has_key?('resultCount') then
      return [] if result['resultCount'] == 0
      r = result['results'][0]
      url = r['trackViewUrl']
      application = r['trackName']
    else
      # XXX: throw exception here?
      return []
    end

    reviews_page = @ua.get(url)
    rating_nodes = reviews_page.parser.xpath("//div[@class='customer-review']")
    return [] if rating_nodes == nil
    rating_nodes.each do |r|
      title = r.xpath("h5/span[@class='customerReviewTitle']/text()").text
      title.sub!(/\s+/i, ' ')
      title.strip!
      user = r.xpath("span[@class='user-info']/text()").text
      user.sub!(/\s+/i, ' ')
      user.strip!
      star_nodes = r.xpath("h5/div/div/span[@class='rating-star']")
      rating = star_nodes.count
      text = r.xpath("p[@class='content more-text']/text()").text
      text.sub!(/\s+/i, ' ')
      text.strip!
      review = AppReview.new( :title => title, :author => user, :text => text, :rating => rating, :market => market, :application => application)
      reviews << review
    end
    return reviews
  end
end

Dir.mkdir(DB_DIR) unless(File.exist?(DB_DIR))
db = FSDB::Database.new(DB_DIR)
known_reviews = db[IDS_TABLE]
if known_reviews == nil then
  known_reviews = []
  db[IDS_TABLE] = known_reviews
end

store = AppStore.new
APPS.each do |app_id|
  store.get_all_reviews(app_id).each do |review|
    next if (known_reviews.include?(review.uid))
    db.edit IDS_TABLE do |list|
      list << review.uid
    end

    body = "#{review.title}\n"
    # \U2605 - star symbol
    body += [0x2605].pack("U*") * review.rating
    body += " #{review.author} (#{review.market})\n"
    body += "--------------------------------\n"
    body += review.text

    Pony.mail( :subject => "User review: #{review.application}",
                :body => body,
                :to => TO_EMAIL,
                :from => FROM_EMAIL,
                :via => :sendmail)
  end
end
