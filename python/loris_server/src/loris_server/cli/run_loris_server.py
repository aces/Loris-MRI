import argparse
import os

import uvicorn


def main():
    parser = argparse.ArgumentParser(
        description="Start the LORIS server",
    )

    parser.add_argument(
        '--config',
        help='Name of the LORIS configuration file')

    parser.add_argument(
        '--dev',
        action='store_true',
        help="Run in development mode with hot reload"
    )

    parser.add_argument(
        '--host',
        default='127.0.0.1',
        help="Host to bind to (default: 127.0.0.1)"
    )

    parser.add_argument(
        '--port',
        type=int,
        default=8000,
        help="Port to bind to (default: 8000)"
    )

    args = parser.parse_args()

    if args.config is not None:
        os.environ['LORIS_CONFIG_FILE'] = args.config

    if args.dev:
        os.environ['LORIS_DEV_MODE'] = 'true'

    uvicorn.run(
        'loris_server.api:api',
        host=args.host,
        port=args.port,
        reload=args.dev,
        log_level='debug' if args.dev else 'info'
    )


if __name__ == '__main__':
    main()
