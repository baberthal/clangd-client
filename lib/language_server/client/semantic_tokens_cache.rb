# frozen_string_literal: true

module LanguageServer
  module Client
    # Simple cache to store semantic tokens that have been retrieved from the
    # server.
    class SemanticTokensCache
      def initialize
        @access_lock = Mutex.new
        invalidate
      end

      def invalidate
        @access_lock.synchronize { invalidate_no_lock }
      end

      alias invalidate! invalidate

      def invalidate_no_lock
        @request_data = nil
        @semantic_tokens = nil
      end

      alias invalidate_no_lock! invalidate_no_lock

      def update(request_data, semantic_tokens)
        @access_lock.synchronize do
          update_no_lock(request_data, semantic_tokens)
        end
      end

      def update_no_lock(request_data, semantic_tokens)
        @request_data = request_data
        @semantic_tokens = semantic_tokens
      end

      def get_semantic_tokens_if_cache_valid(request_data)
        @access_lock.synchronize do
          get_semantic_tokens_if_cache_valid_no_lock(request_data)
        end
      end

      def get_semantic_tokens_if_cache_valid_no_lock(request_data)
        return @semantic_tokens if @request_data && @request_data == request_data

        nil
      end
    end
  end
end
