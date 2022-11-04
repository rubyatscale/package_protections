# PackageProtections

This gem helps us use Packwerk and Rubocop to create well-packaged code.
The intent of this gem is two fold:
1) Provide a coherent modularization interface, where each `package.yml` is the main place you go to configure modularization checks.
2) Create hard-checks for packwerk and rubocop. Packwerk and rubocop support gradual adoption, but they don't support the ability to block adding to the TODO list once a package has fully adhered to a rule.

This gem ships with the following checks
1) Your package is not introducing dependencies that are not intended (via `packwerk` `enforce_dependencies`)
2) Other packages are not using the private API of your package (via `packwerk` `enforce_privacy`)
3) Your package has a typed public API (via the `rubocop` `PackageProtections/TypedPublicApi` cop)
4) Your package only creates a single namespace (via the `rubocop` `PackageProtections/NamespacedUnderPackageName` cop)

## Initial Configuration
Package protections first requires that your application is using [`packwerk`](https://github.com/Shopify/packwerk), [`rubocop`](https://github.com/rubocop/rubocop), and [`rubocop-sorbet`](https://github.com/Shopify/rubocop-sorbet). Follow the regular setup instructions for those tools before proceeding.

Some of our package protections are implemented by rubocop, with their interface in `package.yml` files.
For initial configuration in a new application, you need to tell RuboCop to load the package protections extension:
```yml
# `.rubocop.yml`
inherit_gem:
  package_protections:
    - config/default.yml

require:
  - package_protections
```

## Usage
Today, `PackageProtections` has several built-in protections that you can configure to protect your package.

*By default, all protections are set to fail on new violations. Users need to specifically "opt out" if they do not want a protection.
We want this because we want default behavior to be our vision for well-protected packages, and deviations from the ideal vision should require explicit user action.*
Most protections set their default to `fail_on_new` instead of `fail_on_any` because we want to make it easy for users to split up packages into other ones and improve boundaries incrementally. We recommend packages for totally greenfield features use the `fail_on_any` behavior.

Lastly, note that unless a protection's default behavior is `fail_never`, the protection must explicitly be set.

To change the behavior for these protections, add the correct YAML key under `metadata.protections`. See `Example Usage` below for an example.

### `prevent_this_package_from_violating_its_stated_dependencies`
*This is only available if your package has `enforce_dependencies` set to `true`!*
This protection ensures that your package does not use API from packages that are not listed under `dependencies` in `package.yml`. This helps make sure you manage your dependencies.

### `prevent_other_packages_from_using_this_packages_internals`
*This is only available if your package has `enforce_privacy` set to `true`!*
This protection ensures that OTHER packages do not use the private API of your package. This helps ensure that clients are using your code the way you intend.

### `prevent_this_package_from_exposing_an_untyped_api`
This protection ensures that all files within `app/public` are typed at level `strict`, which means that every file must have a type signature. See https://sorbet.org/docs/static#file-level-granularity-strictness-levels for more information on typed strictness levels. Make sure to generate a TODO list if you want to use the `fail_on_new` violation behavior. See more information on generating a TODO list in the `fail_on_new` subsection under violation behaviors.

### `prevent_this_package_from_creating_other_namespaces`
*This is only available if your package is in `./packs`, `./gems`, `./components`, or `./packages`.*
This helps ensure that your package is only creating one namespace (based on folder hierarchy). This helps organize the public API of your pack into one place.
This protection only looks at files in `packs/your_pack/app` (it ignores spec files).
This protection is implemented via Rubocop -- expect to see results for this when running `rubocop` however you normally do. To add to the TODO list, add to `.rubocop_todo.yml`
Lastly – this protection can be configured by setting `globally_permitted_namespaces`, e.g.:
```ruby
RuboCop::Packs.configure do |config|
  config.globally_permitted_namespaces = ['SomeGlobalNamespace']
end
```

If you've worked through all of the TODOs for this cop and are able to set the value to `fail_on_any`, you can also set `automatic_pack_namespace` which will support your pack having one global namespace without extra subdirectories. That is, instead of `packs/foo/app/services/foo/bar.rb`, you can use `packs/foo/app/services/bar.rb` and still have it define `Foo::Bar`. [See the `stimpack` README.md](https://github.com/rubyatscale/stimpack#readme) for more information.

## Violation Behaviors
#### `fail_on_any`
If this behavior is selected, the build will fail if there is *any* issue, new or old.
#### `fail_on_new`
#### For protections from packwerk
If this behavior is selected, everything that is already in `deprecated_references.yml` is considered allowed. Think of it like `.rubocop_todo.yml`. If your PR introduces a new violation that is not captured in `deprecated_references.yml`, the build will rerun `bin/packwerk check` and fail if a new violation shows up. If for whatever reason you'd like to allow for the new violation, you can simply run `bin/packwerk update-deprecations` locally and commit the changes to `deprecated_references.yml` files.
#### For protections from rubocop
Similar to above, but instead of `deprecated_references.yml`, violations are stored in your `.rubocop_todo.yml` file. You can add to that file to bypass protections at this level.

#### `fail_never`
If this behavior is selected, the protection will not be active.

## Example Usage
This is an example package that is focused on having a typed API that respects other teams' stated boundaries.

```yml
enforce_dependencies: true
enforce_privacy: true
metadata:
  protections:
    prevent_this_package_from_violating_its_stated_dependencies: fail_never
    prevent_other_packages_from_using_this_packages_internals: fail_never
    prevent_this_package_from_exposing_an_untyped_api: fail_on_any
    prevent_this_package_from_creating_other_namespaces: fail_never
```

## PackageProtections.set_defaults!
Calling `PackageProtections.set_defaults!(...)` will make sure that all available protections are set in the protections metadata key without changing any protection behaviors that are already set.

### Example Usage
```ruby
# get your packages
packages = ParsePackwerk.all
# then set defaults
PackageProtections.set_defaults!(packages)
# or just set defaults for one package
PackageProtections.set_defaults!(packages.select{|p| p.package_name == 'packs/my_package'})
```

## Custom Protections

It's possible to create your own custom protections that go through this interface. To do this, you just need to implement a protection and configure `PackageProtections`.

```ruby
PackageProtections.configure do |config|
  config.protections += [MyCustomProtection]
end
```

In this example, `MyCustomProtection` needs to implement the `PackageProtections::ProtectionInterface` (for protections powered by `packwerk` that look at new and existing violations) OR `PackageProtections::RubocopProtectionInterface` (for protections powered by `rubocop` that look at the AST). It's recommended to take a look at the existing protections as examples. If you're having any trouble with this, please file an issue and we'll be glad to help.

## Incorporating into your CI Pipeline
Your CI pipeline can execute the public API and fail if there are any offenses.

## Discussions, Issues, Questions, and More
To keep things organized, here are some recommended homes:
### Issues:
https://github.com/rubyatscale/package_protections/issues

### Questions:
https://github.com/rubyatscale/package_protections/discussions/categories/q-a

### General discussions:
https://github.com/rubyatscale/package_protections/discussions/categories/general

### Ideas, new features, requests for change:
https://github.com/rubyatscale/package_protections/discussions/categories/ideas

### Showcasing your work:
https://github.com/rubyatscale/package_protections/discussions/categories/show-and-tell
