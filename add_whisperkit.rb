require 'xcodeproj'

project_path = '/Users/mujeb/mjvoice/mjvoice.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Create remote package reference
package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
package.repositoryURL = 'https://github.com/argmaxinc/WhisperKit.git'
requirement = {}
requirement['kind'] = 'upToNextMajorVersion'
requirement['minimumVersion'] = '0.14.0'
package.requirement = requirement
project.package_references << package

# Find the ASRService target
target = project.targets.find { |t| t.name == 'ASRService' }

# Create product dependency
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.package = package
product.product_name = 'WhisperKit'
target.add_dependency(product)

project.save