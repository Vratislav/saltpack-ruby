module Saltpack
  b64_alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

  b62_alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'

  b85_alphabet =     '!"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstu'

  here = File.dirname(__FILE__)

  props_file = File.join(here,'unicode','DerivedNormalizationProps.txt')
  categories_file = File.join(here,'unicode','UnicodeData.txt')








  def get_alphabet(args)

  end






  def do_armor(args)
    alphabet = get_alphabet(args)

  end














end