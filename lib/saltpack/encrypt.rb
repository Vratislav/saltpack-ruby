require 'rbnacl/libsodium'
require 'rbnacl'
require 'msgpack'

module Saltpack
  class << self

    # Utility functions
    # -----------------
    def chunks_with_empty(message, chunk_size)
      #The last chunk is empty, which signifies the end of the message
      chunk_start = 0
      chunks = []
      while chunk_start < message.length
        chunks << message[chunk_start..chunk_start+chunk_size-1]
        chunk_start += chunk_size
      end
      #append empty chunk
      chunks << []
      chunks
    end

    def json_repr(obj)

    end


    # All the important bits!
    # -----------------------

    SENDER_KEY_SECRETBOX_NONCE = "saltpack_sender_key_sbox"
    fail() if SENDER_KEY_SECRETBOX_NONCE.length != 24

    PAYLOAD_KEY_BOX_NONCE = "saltpack_payload_key_box"
    fail() if PAYLOAD_KEY_BOX_NONCE.length != 24

    PAYLOAD_NONCE_PREFIX = "saltpack_ploadsb"
    fail() if PAYLOAD_NONCE_PREFIX.length != 16

    def encrypt(sender_private, recipient_public_keys, message, chunk_size, visible_recipients=False)
      #keys generation
      #sender_public = nacl.bindings.crypto_scalarmult_base(sender_private)
      sender_public = RbNaCl::PrivateKey.new(sender_private).public_key

      ephemeral_private = RbNaCl::PrivateKey.new(RbNaCl::Random.random_bytes(32))
      #ephemeral_public = nacl.bindings.crypto_scalarmult_base(ephemeral_private)
      ephemeral_public = ephemeral_private.public_key

      payload_key = RbNaCl::Random.random_bytes(32)


      #Sender secretbox
      # sender_secretbox = nacl.bindings.crypto_secretbox(
      #     message=sender_public,
      #     nonce=SENDER_KEY_SECRETBOX_NONCE,
      #     key=payload_key)
      sender_secretbox = RbNaCl::SecretBox.new(payload_key)
      sender_secretpbox_ciphertext = sender_secretbox.encrypt(SENDER_KEY_SECRETBOX_NONCE,sender_public)

      recipient_pairs = []
      recipient_public_keys.each do |recipient_public_key|

        # The recipient box holds the sender's long-term public key and the
        # symmetric message encryption key. It's encrypted for each recipient
        # with the ephemeral private key.
        # payload_key_box = nacl.bindings.crypto_box(
        #     message=payload_key,
        #     nonce=PAYLOAD_KEY_BOX_NONCE,
        #     pk=recipient_public,
        #     sk=ephemeral_private)
        payload_key_box = RbNaCl::Box.new(recipient_public_key, ephemeral_private)
        payload_key_box_ciphertext = payload_key_box.encrypt(PAYLOAD_KEY_BOX_NONCE, payload_key)


        # Nil is in the place of recipient public key. which is optional
        if visible_recipients
          pair = [recipient_public_key, payload_key_box]
        else
          pair = [None, payload_key_box]
        end
        recipient_pairs << pair
      end

      header = [
          "saltpack",
          [1, 0],
          0,
          ephemeral_public,
          sender_secretbox,
          recipient_pairs
      ]
      header_bytes = header.to_msgpack
      header_hash = RbNaCl::Hash.sha512(header_bytes)
      double_encoded_header_bytes = header_bytes.to_msgpack

      output = StringIO.new
      output.write double_encoded_header_bytes

      #Compute the per-user MAC key
      recipient_mac_keys = []
      mac_keys_nonce = header_hash[0..24]
      recipient_public_keys.each do |recipient_public_key|
        mac_key_box = RbNaCl::Box.new(recipient_public_key, sender_private)
        mac_key_box_ciphertext = mac_key_box.encrypt(mac_key_nonce,("\0"*32).encode('binary'))
        mac_key = mac_key_box_ciphertext[16..48]
        recipient_public_keys << mac_key
      end

      # Write the chunks.
      chunks = chunks_with_empty(message, chunk_size)
      chunks.each_with_index do |chunk, chunknum|
        payload_nonce = PAYLOAD_NONCE_PREFIX + bigendian_int_to_bytes(chunknum,8).pack('C*')
        payload_secretbox = RbNaCl::SecretBox.new(payload_key)
        payload_secretbox_ciphertext = payload_secretbox.encrypt(payload_nonce,chunk)
        # Authenticate the hash of the payload for each recipient.
        payload_hash = RbNaCl::Hash.sha512(header_hash+payload_nonce+payload_secretbox_ciphertext)
        hash_authenticators = []
        recipient_mac_keys.each do |mac_key|
           hmac = RbNaCl::HMAC::SHA512256.new(mac_key)
        end

      end



    end


  end
end


