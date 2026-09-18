#!/bin/sh
cd `dirname $0`
cd ..
BASEDIR=`pwd`
PLUGIN_NAME=`basename $BASEDIR`

if [ ! -f ~/.bashrc ]; then
    cd ~/
    tar xfz /.home.tgz
    cd $BASEDIR 
fi

echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bashrc

if [ -f .devcontainer/redmine.code-workspace ] && grep -q '"/usr/local/redmine/plugins/dummy"' .devcontainer/redmine.code-workspace; then
    sed -i.bak "s|\"/usr/local/redmine/plugins/dummy\"|\"/usr/local/redmine/plugins/$PLUGIN_NAME\"|g" .devcontainer/redmine.code-workspace
    rm .devcontainer/redmine.code-workspace.bak
fi

if [ ! -f .devcontainer/.env ] || ! grep -q "^PLUGIN_NAME=" .devcontainer/.env; then
    echo "PLUGIN_NAME=$PLUGIN_NAME" >> .devcontainer/.env
    echo "##### Rebuild the container to apply the changes. #####"
    exit 0
fi

# The base image's .bashrc sources nvm.sh and runs `nvm use` on every shell
# start. `nvm use` rescans the whole PATH with a regex, which is slow, and tools
# that probe the environment with `bash -i -c ...` spawn dozens of shells at
# once -- enough to pin every core in the VM. Load nvm lazily instead.
if ! grep -q 'nvm-lazy-load' $HOME/.bashrc; then
    sed -i \
        -e 's|^\( *\)\. "$NVM_DIR/nvm.sh"|\1: # nvm-lazy-load|' \
        -e 's|^\( *\)nvm use --silent default.*|\1: # nvm-lazy-load|' \
        -e 's|^\( *\)\. "$NVM_DIR/bash_completion"|\1: # nvm-lazy-load|' \
        $HOME/.bashrc
    cat >> $HOME/.bashrc <<'EOS'

# nvm-lazy-load: put the installed Node on PATH by glob, and defer sourcing
# nvm.sh until `nvm` is actually invoked.
for __d in "$NVM_DIR"/versions/node/*/bin; do
    [ -d "$__d" ] && __nvm_bin="$__d"
done
[ -n "$__nvm_bin" ] && export PATH="$__nvm_bin:$PATH"
unset __d __nvm_bin

nvm() {
    unset -f nvm
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
    nvm "$@"
}
EOS
fi

lefthook install


rm -rf .ruby-lsp
ln -s /dev/null .ruby-lsp
rm -f /usr/local/redmine/.rubocop.yml

npm ci

cd $REDMINE_ROOT

rm -rf .ruby-lsp
ln -s /dev/null .ruby-lsp

cd $REDMINE_ROOT

git pull

if [ ! -f "$BASEDIR/init.rb" ]; then
    bash "$BASEDIR/.devcontainer/plugin_generator.sh"
fi

bundle install 

initdb() {
    rm -f db/schema.rb
    bundle exec rake db:create
    bundle exec rake db:migrate
    bundle exec rake redmine:plugins:migrate

    bundle exec rake db:drop RAILS_ENV=test
    bundle exec rake db:create RAILS_ENV=test
    bundle exec rake db:migrate RAILS_ENV=test
    bundle exec rake redmine:plugins:migrate RAILS_ENV=test
}

initdb

export DB=mysql2
export DB_NAME=redmine
export DB_USERNAME=root
export DB_PASSWORD=root
export DB_HOST=mysql
export DB_PORT=3306

initdb

export DB=postgresql
export DB_NAME=redmine
export DB_USERNAME=postgres
export DB_PASSWORD=postgres
export DB_HOST=postgres
export DB_PORT=5432

initdb