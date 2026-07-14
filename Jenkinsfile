// This runs on a Docker-based Jenkins controller.
////
// FLAW 2: every stage dumps its output to a .log file (build.log, push.log,
// deploy.log) and then uploads that file to S3 on top of what Jenkins already
// keeps in its own console log. That's three extra PutObject calls per build,
// and since nothing expires objects under the pipeline/ prefix, they just pile
// up forever, quietly driving up S3 storage and request costs. Fix is either
// to drop the aws s3 cp lines, or add a lifecycle rule that expires pipeline/
// objects after 30 days.
pipeline {
    agent any

    environment {
        AWS_REGION    = 'eu-central-1'

        // pulled from Jenkins credentials store
        ECR_REGISTRY  = credentials('ecr-registry-url')
        SNS_TOPIC_ARN = credentials('sns-topic-arn')
        LOG_BUCKET    = credentials('log-bucket-name')

        // just app-level naming, nothing sensitive
        ECR_REPO      = 'cloud-app'
        ECS_CLUSTER   = 'cloud-app-cluster'
        ECS_SERVICE   = 'cloud-app-svc'
    }

    stages {
        stage('Checkout') {
      steps {
        checkout scm
      }
        }

        stage('Build image') {
      steps {
        sh '''
                    docker build \
                        -f Docker/Dockerfile \
                        -t ${ECR_REPO}:${BUILD_NUMBER} . \
                        > build.log 2>&1

                    cat build.log

                    aws s3 cp build.log \
                        s3://${LOG_BUCKET}/pipeline/docker-build/${BUILD_NUMBER}.log \
                        --quiet
                '''
      }
        }

        stage('Push to ECR') {
      steps {
        sh '''
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login \
                        --username AWS \
                        --password-stdin ${ECR_REGISTRY}

                    docker tag \
                        ${ECR_REPO}:${BUILD_NUMBER} \
                        ${ECR_REGISTRY}/${ECR_REPO}:${BUILD_NUMBER}

                    docker tag \
                        ${ECR_REPO}:${BUILD_NUMBER} \
                        ${ECR_REGISTRY}/${ECR_REPO}:latest

                    docker push \
                        ${ECR_REGISTRY}/${ECR_REPO}:${BUILD_NUMBER} \
                        > push.log 2>&1

                    docker push \
                        ${ECR_REGISTRY}/${ECR_REPO}:latest \
                        >> push.log 2>&1

                    cat push.log

                    aws s3 cp push.log \
                        s3://${LOG_BUCKET}/pipeline/docker-push/${BUILD_NUMBER}.log \
                        --quiet
                '''
      }
        }

        stage('Deploy to ECS') {
      steps {
        sh '''
                    aws ecs update-service \
                        --cluster ${ECS_CLUSTER} \
                        --service ${ECS_SERVICE} \
                        --force-new-deployment \
                        --region ${AWS_REGION} \
                        > deploy.log 2>&1

                    cat deploy.log

                    aws s3 cp deploy.log \
                        s3://${LOG_BUCKET}/pipeline/deploy/${BUILD_NUMBER}.log \
                        --quiet
                '''
      }
        }

        stage('Health check') {
      environment {
        ALB_DNS_NAME = credentials('app-alb-dns-name')
      }

      steps {
        sh 'bash scripts/verify_health.sh'
      }
        }
    }

    post {
        success {
      sh '''
                aws sns publish \
                    --topic-arn ${SNS_TOPIC_ARN} \
                    --subject "Pipeline SUCCESS: build ${BUILD_NUMBER}" \
                    --message "Deployment of build ${BUILD_NUMBER} succeeded." \
                    --region ${AWS_REGION}
            '''
        }

        failure {
      sh '''
                aws sns publish \
                    --topic-arn ${SNS_TOPIC_ARN} \
                    --subject "Pipeline FAILURE: build ${BUILD_NUMBER}" \
                    --message "Build ${BUILD_NUMBER} failed. Check Jenkins console output." \
                    --region ${AWS_REGION}
            '''
        }

        unstable {
      sh '''
                aws sns publish \
                    --topic-arn ${SNS_TOPIC_ARN} \
                    --subject "Pipeline UNSTABLE: build ${BUILD_NUMBER}" \
                    --message "Build ${BUILD_NUMBER} completed with warnings." \
                    --region ${AWS_REGION}
            '''
        }
    }
}
