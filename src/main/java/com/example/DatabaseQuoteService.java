package com.example;

import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

@Service
public class DatabaseQuoteService implements QuoteService {

    private final QuoteRepository quoteRepository;

    public DatabaseQuoteService(QuoteRepository quoteRepository) {
        this.quoteRepository = quoteRepository;
    }

    public Quote randomQuote() {
        return this.quoteRepository.findRandomQuote();
    }
}
