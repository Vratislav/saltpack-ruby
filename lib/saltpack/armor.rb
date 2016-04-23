module Saltpack
  class << self
    B64_ALPHAPBET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

    B62_ALPHAPBET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'

    B85_ALPHAPBET = '!"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstu'

    here = File.dirname(__FILE__)

    props_file = File.join(here, 'unicode', 'DerivedNormalizationProps.txt')
    categories_file = File.join(here, 'unicode', 'UnicodeData.txt')


    def get_alphabet(args)
      alphabet = B62_ALPHAPBET
      if args[:alphabet]
        alphabet = args[:alphabet]
      elsif args[:base64]
        alphabet = B64_ALPHAPBET
      elsif args[:base85]
        alphabet = B85_ALPHAPBET
      elsif args[:twitter]
        fail('Twitter alphabet is not supported yet')
      end
      alphabet
    end


    def get_bytes_in(args)
      if args[:bytes_in] != nil
        puts "String encoding of input is #{args[:bytes_in].encoding} "
        #we probably do not need to use .encode().
        # String in ruby is already in UTF8
        return args[:bytes_in].bytes
      end
      STDIN.read
    end


    def get_block_size(args)
      block_size = 32
      if args[:block]
        block_size = args[:block].to_i
      elsif args[:base64]
        block_size = 3
      elsif args[:base85]
        block_size = 4
      elsif args[:twitter]
        block_size = 351
      end
      block_size
    end


    def chunk_iterable(bytes, block_size)
      fail('Block size must be greater than 0') if block_size <= 0
      chunks = []
      i = 0
      while i < bytes.length
        chunk = bytes[i..i+block_size-1]
        #puts "Putted chunk #{chunk}"
        chunks << chunk
        i = i + block_size
      end
      chunks
    end


    def max_bytes_size(alphabet_size, chars_size)
      ###
      # The most bytes we can represent satisfies this:
      #    256 ^ bytes_size <= alphabet_size ^ chars_size
      # Take the log_2 of both sides:
      #    8 * bytes_size <= log_2(alphabet_size) * chars_size
      # Solve for the maximum bytes_size:
      return (Math.log2(alphabet_size) / 8.0 * chars_size.to_f).floor
    end

    def min_chars_size(alphabet_size, bytes_size)
      ###
      # The most bytes we can represent satisfies this:
      #   256 ^ bytes_size <= alphabet_size ^ chars_size
      # Take the log_2 of both sides:
      #   8 * bytes_size <= log_2(alphabet_size) * chars_size
      # Solve for the minimum chars_size:
      return (8*bytes_size/Math.log2(alphabet_size)).ceil
    end

    def extra_bits(alphabet_size, chars_size, bytes_size)
      #In order to be compatible with Base64, when we write a partial block, we
      #need to shift as far left as we can. Figure out how many whole extra bits
      #the encoding space has relative to the bytes coming in.'''
      total_bits = (Math.log2(alphabet_size)*chars_size).floor
      total_bits - 8*bytes_size
    end

    def encode_block(bytes_block, alphabet, shift=false)
      # Figure out how wide the chars block needs to be, and how many extra bits
      # we have.
      #puts("bytes_block #{bytes_block}")
      chars_size = min_chars_size(alphabet.length, bytes_block.length)
      puts "Chars size during encoding #{chars_size}"
      #puts "alphabet #{alphabet}"
      #puts 'chars size:'
      #puts chars_size
      extra = extra_bits(alphabet.length, chars_size, bytes_block.length)
      # Convert the bytes into an integer, big-endian.
      # See: http://www.rubydoc.info/stdlib/core/Array:pack
      #puts 'bytes block:'
      #puts bytes_block
      bytes_int = bytes_to_bigendian_int(bytes_block)
      #puts 'bytes int:'
      #puts bytes_int
      if shift
        #bytes_int <<= extra
        bytes_int = bytes_int << extra
      end

      # Convert the result into our base
      places = []
      for place in (1..chars_size)
        reminder = bytes_int%alphabet.length
        places.insert(0, reminder)
        #Floor division
        bytes_int = bytes_int / alphabet.length.to_i
      end
      #puts "Places array:#{places}"
      places.map { |x| alphabet[x] }.join('')
    end

    def chunk_string_ignoring_whitespace(s, size)
      #Skip over whitespace when assembling chunks
      fail() if size <= 1
      chunks = []
      chunk = ''
      s.each_char do |char|
        if char == " "
          next
        end
        chunk += char
        if chunk.length == size
          chunks << chunk
          chunk = ''
        end
      end
      if chunk != ''
        chunks << chunk
      end
      chunks
    end

    def get_char_index(alphabet, char)
      #This is the same as alphabet.index(char) but error is raised when char is not found
      #in the given alphabet
      index = alphabet.index(char)
      raise IndexError.new("Could not find #{char} in alphabet #{alphabet}") if index == nil
      index
    end

    def decode_block(chars_block, alphabet, shift=false)
      # Figure out how many bytes we have, and how many extra bits they'll have
      # been shifted by.
      bytes_size = max_bytes_size(alphabet.length, chars_block.length)
      expected_char_size = min_chars_size(alphabet.length, bytes_size)

      puts "Decoding block #{chars_block}, bytes_size #{bytes_size}"

      if chars_block.length != expected_char_size
        fail("illegal chars size #{chars_block.length}, expected #{expected_char_size}")
      end

      extra = extra_bits(alphabet.length, chars_block.length, bytes_size)
      #Convert the chars to an integer.
      bytes_int = get_char_index(alphabet, chars_block[0])
      chars_block[1..chars_block.length-1].each_char { |c|
        bytes_int *= alphabet.length
        bytes_int += get_char_index(alphabet, c)
      }
      if shift
        bytes_int = bytes_int >> extra
      end
      #Convert the result to bytes, big_endian
      bytes = bigendian_int_to_bytes(bytes_int, bytes_size)
      #puts "Bytes #{bytes}"
      bytes
    end


    def armor(input_bytes, alphabet=B62_ALPHAPBET, block_size=32, raw=false, shift=false, message_type='MESSAGE')
      chunks = chunk_iterable(input_bytes, block_size)
      output = ''
      chunks.each do |chunk|
        output += encode_block(chunk, alphabet, shift)
      end
      if raw
        return chunk_iterable(output, 43).join(' ')
      end
      #puts "output: #{output}"
      words = chunk_iterable(output, 15)
      sentences = chunk_iterable(words, 200)
      joined = sentences.map { |sentence| sentence.join(' ') }.join('\n')
      header = "BEGIN SALTPACK #{message_type}. "
      footer = ". END SALTPACK #{message_type}."
      header + joined + footer
    end

    def dearmor(input_chars, alphabet=B62_ALPHAPBET, char_block_size=43, raw=false, shift=false)
      puts "Input in armor #{input_chars}"
      unless raw
        #Find the substring between the first periods
        first_period = input_chars.index('.')
        if first_period == nil
          STDERR.puts 'No period found in input.'
          exit(1)
        end
        second_period = input_chars.index('.', first_period+1)
        if second_period == nil
          STDERR.puts 'No second period found in input.'
          exit(1)
        end
        input_chars = input_chars[first_period+1..second_period-1]
      end
      puts "Dearmoring #{input_chars}"
      chunks = chunk_string_ignoring_whitespace(input_chars, char_block_size)
      output = []
      chunks.each do |chunk|
        output << decode_block(chunk, alphabet, shift=shift)
      end
      output
    end


    def bytes_to_bigendian_int(bytes)
      result = 0
      base = (bytes.count-1) * 8
      #puts bytes
      bytes.each do |byte|
        result = result | ((byte) << base)
        #puts "result: #{result} base: #{base}"
        base = base - 8
      end
      result
    end

    def bigendian_int_to_bytes(int, bytes_count)
      bytes = []
      (0..bytes_count-1).reverse_each do |i|
        base = i*8
        byte = (int >> base)
        int = int - (byte << base)
        bytes << byte
        #puts "base is #{base}, byte #{byte}"
      end
      bytes
    end


    def efficient_chars_sizes(alphabet_size, chars_size_upper_bound)
      out = []
      max_efficiency = 0
      (1..chars_size_upper_bound).each do |chars_size|
        bytes_size = max_bytes_size(alphabet_size, chars_size)
        efficiency = bytes_size / chars_size.to_f
        # This check also excludes sizes too small to encode a single byte
        if efficiency > max_efficiency
          out << {chars_size: chars_size, bytes_size: bytes_size, efficiency: efficiency}
          max_efficiency = efficiency
        end
      end
      out
    end

    def print_efficient_chars_sizes(alphabet_size, chars_size_upper_bound)
      puts "efficient block sizes for alphabet size #{alphabet_size}"
      efficiencies = efficient_chars_sizes(alphabet_size, chars_size_upper_bound)
      efficiencies.each do |e|
        bytes = e[:bytes_size].to_s.rjust 2
        chars = e[:chars_size].to_s.rjust 2
        percentage = (e[:efficiency]*100).round(2).to_s.rjust 2
        puts "#{bytes} bytes: #{chars} chars (#{percentage}%)"
      end
    end


    def do_efficient(args)
      if args[:max_size] == nil
        upper_bound = 50
      else
        upper_bound = args[:max_size].to_i
      end
      alphabet_size = args[:alphabet_size].to_i
      print_efficient_chars_sizes(alphabet_size, upper_bound)
    end

    def do_armor(args)
      alphabet = get_alphabet(args)
      bytes_input = get_bytes_in(args)
      shift = args[:shift] != nil
      raw = args[:raw] != nil
      block_size = get_block_size(args)
      armored = armor(bytes_input, alphabet, block_size, raw, shift)
      puts armored
    end

    def do_dearmor(args)
      alphabet = get_alphavet(args)
      chars_in = get_chars_in(args)
      shift = args[:shift] != nil
      raw = args[:raw] != nil
      char_block_size = min_chars_size(alphabet.length, get_block_size(args))
      dearmored = dearmor(chars_in, alphabet, char_block_size, raw, shift)
      STDOUT.write dearmored
    end


  end


end

#puts "Should be #{24929}"
#puts Saltpack.bigendian_int_to_bytes(Saltpack.bytes_to_bigendian_int([90,255]),2)

#puts "Heh #{'aaa'.unpack("s*")}"
#puts Saltpack.armor('ahoj'.bytes)
#puts Saltpack.dearmor('BEGIN SALTPACK MESSAGE. 1mb4yQ. END SALTPACK MESSAGE.')
Saltpack.do_efficient({alphabet_size: 62})
