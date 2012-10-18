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
require 'digest/md5'
require 'pony'
require 'fsdb'
require 'json'

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
  attr_accessor :author, :title, :text, :rating, :market, :application, :date
  def initialize(args = {})
    args.each { |key,value| send("#{key}=", value) }  
  end
  def uid
    return Digest::MD5.hexdigest("#{@author}#{@title}#{@text}#{@rating}#{@market}")
  end
end

class AppStore
  @@markets = {
    'Argentina' => 143505,
    'Armenia' => 143524,
    'Australia' => 143460,
    'Austria' => 143445,
    'Belgium' => 143446,
    'Botswana' => 143525,
    'Brazil' => 143503,
    'Bulgaria' => 143526,
    'Canada' => 143455,
    'Chile' => 143483,
    'China' => 143465,
    'Colombia' => 143501,
    'Costa Rica' => 143495,
    'Croatia' => 143494,
    'Czech Republic' => 143489,
    'Denmark' => 143458,
    'Dominican Rep.' => 143508,
    'Ecuador' => 143509,
    'Egypt' => 143516,
    'El Salvador' => 143506,
    'Estonia' => 143518,
    'Finland' => 143447,
    'France' => 143442,
    'Germany' => 143443,
    'Greece' => 143448,
    'Guatemala' => 143504,
    'Honduras' => 143510,
    'Hong Kong' => 143463,
    'Hungary' => 143482,
    'India' => 143467,
    'Indonesia' => 143476,
    'Ireland' => 143449,
    'Israel' => 143491,
    'Italy' => 143450,
    'Jamaica' => 143511,
    'Japan' => 143462,
    'Jordan' => 143528,
    'Kazakhstan' => 143517,
    'Kenya' => 143529,
    'Korea' => 143466,
    'Kuwait' => 143493,
    'Latvia' => 143519,
    'Lebanon' => 143497,
    'Lithuania' => 143520,
    'Luxembourg' => 143451,
    'Macau' => 143515,
    'Macedonia' => 143530,
    'Madagascar' => 143531,
    'Malaysia' => 143473,
    'Mali' => 143532,
    'Malta' => '143521',
    'Mauritius' => 143533,
    'Mexico' => 143468,
    'Moldova' => 143523,
    'Netherlands' => 143452,
    'New Zealand' => 143461,
    'Nicaragua' => 143512,
    'Niger' => 143534,
    'Norway' => 143457,
    'Pakistan' => 143477,
    'Panama' => 143485,
    'Paraguay' => 143513,
    'Peru' => 143507,
    'Philippines' => 143474,
    'Poland' => 143478,
    'Portugal' => 143453,
    'Qatar' => 143498,
    'Romania' => 143487,
    'Russia' => 143469,
    'Saudi Arabia' => 143479,
    'Senegal' => 143535,
    'Singapore' => 143464,
    'Slovakia' => 143496,
    'Slovenia' => 143499,
    'South Africa' => 143472,
    'Spain' => 143454,
    'Sri Lanka' => 143486,
    'Sweden' => 143456,
    'Switzerland' => 143459,
    'Taiwan' => 143470,
    'Thailand' => 143475,
    'Tunisia' => 143536,
    'Turkey' => 143480,
    'Uganda' => 143537,
    'United Kingdom' => 143444,
    'United Arab Emirates' => 143481,
    'Uruguay' => 143514,
    'USA' => 143441,
    'Venezuela' => 143502,
    'Vietnam' => 143471
  };

  def get_all_reviews(appid)
    reviews = Array.new
    @@markets.keys.each do |m|
      reviews += get_market_reviews(appid, m)
    end
    return reviews
  end

  def get_market_reviews(appid, market)
    reviews = Array.new
    code = @@markets[market]

    p "#{appid} -- #{market}"
    ua = Mechanize.new { |agent|
      agent.user_agent = 'iTunes/10.2.1 (Windows; Microsoft Windows XP Professional Service Pack 3 (Build 2600)) AppleWebKit/533.21.1'
      # agent.log = Logger.new(STDERR)
    }

    ua.pre_connect_hooks << lambda do |params|
      params[:request]['X-Apple-Store-Front'] = "#{code}-1,12"
    end

    ns = {'itms' => 'http://www.apple.com/itms/'}
    json_info = ua.get("http://ax.itunes.apple.com/WebObjects/MZStoreServices.woa/wa/wsLookup?id=#{appid}&country=us")
    result = JSON.parse(json_info.body)
    application = "app#{appid}"
    if result.has_key?('resultCount') then
      if result['resultCount'] > 0 then
        r = result['results'][0]
        application = r['trackName']
      end
    end

    application.sub!(/\s+/i, ' ')
    application.strip!

    attempts = 10
    failed = true
    while failed and (attempts > 0) do
      begin 
        page = ua.get("http://ax.phobos.apple.com.edgesuite.net/WebObjects/MZStore.woa/wa/customerReviews?displayable-kind=11&id=#{appid}&sort=4")
        failed = false
      rescue Mechanize::ResponseCodeError
        puts "Failed, sleep 2 seconds before retrying..."
        sleep(2)
        attempts -= 1
      end
    end

    doc = Nokogiri::XML("<foo>#{page.body}</foo>")

    all_reviews = doc.xpath('//div[@class="paginate all-reviews"]')
    rating_nodes = all_reviews.xpath('div/div/div[@class="customer-review"]')
    return [] if rating_nodes == nil
    rating_nodes.each do |r|
      title_node = r.xpath('h5/span[@class="customerReviewTitle"]')
      title = title_node.text
      title.sub!(/\s+/i, ' ')
      title.strip!
      user_node = r.xpath('span/a[@class="reviewer"]')
      user = user_node.text
      user.sub!(/\s+/i, ' ')
      user.strip!
      next if (user == '')
      date_node = r.xpath('span[@class="user-info"]')
      s = date_node.text
      lines = s.split("\n")
      date = lines[-3]
      date.sub!(/\s+/i, '')
      star_nodes = r.xpath('h5/div/div/span[@class="rating-star"]')
      rating = star_nodes.count
      text = r.xpath('p[@class="content more-text"]').text
      text = r.xpath('p[@class="content"]').text if (text == '')
      text.sub!(/\s+/i, ' ')
      text.strip!
      review = AppReview.new( :title => title, :author => user, :text => text, :rating => rating, :market => market, :application => application, :date => date)
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
    p review.uid
    next if (known_reviews.include?(review.uid))
    db.edit IDS_TABLE do |list|
      list << review.uid
    end

    body = "#{review.title}\n"
    # \U2605 - star symbol
    body += [0x2605].pack("U*") * review.rating
    body += " #{review.author} (#{review.market}), #{review.date}\n"
    body += "--------------------------------\n"
    body += review.text

    Pony.mail( :subject => "User review: #{review.application}",
                :body => body,
                :to => TO_EMAIL,
                :from => FROM_EMAIL,
                :via => :sendmail)
  end
end
