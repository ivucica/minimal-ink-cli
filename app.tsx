import React, { useState } from 'react';
import { render, Text, Box } from 'ink';
// Note: TextInput requires the ink-text-input package in standard setups
import TextInput from 'ink-text-input';

const NameForm = () => {
  const [name, setName] = useState('');
  const [submitted, setSubmitted] = useState(false);

  const handleSubmit = () => {
    if (name.trim()) {
      setSubmitted(true);
    }
  };

  if (submitted) {
    return <Text color="green">Hello {name}!</Text>;
  }

  return (
    <Box flexDirection="column">
      <Text>Please enter your name:</Text>
      <TextInput
        value={name}
        onChange={setName}
        onSubmit={handleSubmit}
        placeholder="Your name"
      />
    </Box>
  );
};

// Render the app to the terminal
render(<NameForm />);
