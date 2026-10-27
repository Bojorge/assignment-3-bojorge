CC ?= gcc
CFLAGS ?= -Wall -Werror -Wextra -g

TARGET := writer

all: $(TARGET)

$(TARGET): writer.c
	$(CC) $(CFLAGS) -o $(TARGET) writer.c

clean:
	rm -f $(TARGET)

.PHONY: all clean
